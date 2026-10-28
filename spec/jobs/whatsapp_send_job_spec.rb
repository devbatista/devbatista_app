require "rails_helper"

RSpec.describe WhatsappSendJob do
  let(:account) { create(:whatsapp_account, status: "connected") }
  let(:conversation) { create(:whatsapp_conversation, account: account, wa_id: "5511991023344", bsuid: nil, last_inbound_at: 1.hour.ago, last_message_at: 1.hour.ago) }
  let(:accepted) do
    graph_response(200, { "messaging_product" => "whatsapp", "contacts" => [ { "input" => "5511991023344", "wa_id" => "5511991023344", "user_id" => "BR.118034776612" } ],
                          "messages" => [ { "id" => "wamid.ENVIADA1", "message_status" => "accepted" } ] })
  end

  def outbound(**attributes)
    create(:whatsapp_message, :outbound, conversation: conversation, status: "pending", wa_message_id: nil, **attributes)
  end

  it "envia texto citando a mensagem, grava o wamid e completa o BSUID da conversa" do
    message = outbound(body: "Confirmando: terça às 10h. https://meet.example.com", reply_to_wa_message_id: "wamid.CITADA")
    requests = stub_graph(accepted)

    described_class.perform_now(message)

    body = json_body(requests.first)
    expect(body).to include("to" => "5511991023344", "type" => "text", "context" => { "message_id" => "wamid.CITADA" })
    expect(body["text"]).to eq("body" => "Confirmando: terça às 10h. https://meet.example.com", "preview_url" => true)
    expect(message.reload).to have_attributes(wa_message_id: "wamid.ENVIADA1", status: "pending")
    expect(conversation.reload.bsuid).to eq("BR.118034776612")
  end

  it "sobe a mídia e envia com legenda, guardando o ID da mídia" do
    message = outbound(kind: "document", body: "Segue o escopo", media_mime_type: "application/pdf", media_filename: "escopo.pdf")
    message.media.attach(io: StringIO.new("%PDF"), filename: "escopo.pdf", content_type: "application/pdf")
    requests = stub_graph(graph_response(200, { "id" => "MEDIA123" }), accepted)

    described_class.perform_now(message)

    expect(requests.first.path).to eq("/v26.0/#{account.phone_number_id}/media")
    expect(json_body(requests.last)["document"]).to eq("id" => "MEDIA123", "caption" => "Segue o escopo", "filename" => "escopo.pdf")
    expect(message.reload).to have_attributes(media_id: "MEDIA123", wa_message_id: "wamid.ENVIADA1")
  end

  it "envia template com o corpo, o cabeçalho de mídia e o sufixo do botão" do
    create(:whatsapp_template, account: account, name: "lembrete_proposta", components: [
      { "type" => "HEADER", "format" => "DOCUMENT" }, { "type" => "BODY", "text" => "Olá, {{1}}. A proposta {{2}} vence amanhã." },
      { "type" => "BUTTONS", "buttons" => [ { "type" => "URL", "text" => "Ver", "url" => "https://admin.devbatista.com/p/{{1}}" } ] }
    ])
    message = outbound(kind: "template", template_name: "lembrete_proposta", template_language: "pt_BR", body: "Olá, Beatriz.", media_filename: "proposta.pdf",
                       template_params: { "body" => [ "Beatriz", "Novo site" ], "buttons" => { "0" => "p/P-2026-029" }, "header_media" => "document" })
    message.media.attach(io: StringIO.new("%PDF"), filename: "proposta.pdf", content_type: "application/pdf")
    requests = stub_graph(graph_response(200, { "id" => "MEDIA9" }), accepted)

    described_class.perform_now(message)

    expect(json_body(requests.last)["template"]).to eq(
      "name" => "lembrete_proposta", "language" => { "code" => "pt_BR" },
      "components" => [
        { "type" => "header", "parameters" => [ { "type" => "document", "document" => { "id" => "MEDIA9", "filename" => "proposta.pdf" } } ] },
        { "type" => "body", "parameters" => [ { "type" => "text", "text" => "Beatriz" }, { "type" => "text", "text" => "Novo site" } ] },
        { "type" => "button", "sub_type" => "url", "index" => "0", "parameters" => [ { "type" => "text", "text" => "p/P-2026-029" } ] }
      ]
    )
    expect(message.reload.wa_message_id).to eq("wamid.ENVIADA1")
  end

  it "nunca envia de novo a mensagem que já tem wamid" do
    stub_graph # uma chamada falharia o teste
    described_class.perform_now(outbound(wa_message_id: "wamid.JA"))
    described_class.perform_now(outbound(status: "sent"))
  end

  it "com a janela fechada na Meta (131047), falha e fecha a janela na tela" do
    message = outbound(body: "Oi")
    stub_graph(graph_error(400, 131_047, "Re-engagement message"))

    expect { described_class.perform_now(message) }.not_to have_enqueued_job(described_class)

    expect(message.reload).to have_attributes(status: "failed", error_code: "131047", error_message: "A janela de 24h está fechada. Envie um template aprovado.")
    expect(conversation.reload).not_to be_window_open
  end

  it "com o BSUID recusado (131062), sugere o template ou o telefone" do
    message = outbound(body: "Oi")
    stub_graph(graph_error(400, 131_062, "Business-scoped user ID not supported"))
    described_class.perform_now(message)
    expect(message.reload.error_message).to eq("Esta mensagem não pode ser enviada sem o telefone do contato. Envie um template ou use o telefone do contato, se ele compartilhar.")
  end

  it "com o token inválido (190), falha e leva a conta para Reconectar necessário" do
    message = outbound(body: "Oi")
    stub_graph(graph_error(401, 190, "Error validating access token"))
    described_class.perform_now(message)
    expect(message.reload).to have_attributes(status: "failed", error_code: "190")
    expect(account.reload).to be_reconnect_required
  end

  it "recusa antes de chamar a Meta quando a conta não está conectada" do
    message = outbound(body: "Oi")
    account.update!(status: "disconnected")
    stub_graph
    described_class.perform_now(message)
    expect(message.reload).to have_attributes(status: "failed", error_message: a_string_including("O número está desconectado"))
  end

  it "tenta de novo a falha transitória, mantendo Enviando, e falha quando as tentativas acabam" do
    message = outbound(body: "Oi")
    stub_graph(graph_error(503, 2, "Service temporarily unavailable"))
    expect { described_class.perform_now(message) }.to have_enqueued_job(described_class).with(message)
    expect(message.reload).to have_attributes(status: "pending", wa_message_id: nil)

    stub_graph(*Array.new(5) { graph_error(503, 2, "Service temporarily unavailable") })
    perform_enqueued_jobs { described_class.perform_later(message) }
    expect(message.reload).to have_attributes(status: "failed", error_message: "Service temporarily unavailable")
  end

  describe "falha de rede no envio" do
    it "sem confirmação da Meta (ReadTimeout no POST), falha sem nova tentativa e sem segundo POST" do
      message = outbound(body: "Oi")
      requests = stub_graph(Net::ReadTimeout)

      expect { described_class.perform_now(message) }.not_to have_enqueued_job(described_class)

      expect(requests.size).to eq(1)
      expect(message.reload).to have_attributes(status: "failed", error_code: nil, wa_message_id: nil,
                                                error_message: "A Meta não confirmou o envio. Ele pode ter chegado ao contato: confira antes de tentar de novo.")
    end

    it "com o pedido sem sair (OpenTimeout), tenta de novo e envia uma vez" do
      message = outbound(body: "Oi")
      requests = stub_graph(Net::OpenTimeout, accepted)

      perform_enqueued_jobs { described_class.perform_later(message) }

      expect(requests.size).to eq(2)
      expect(message.reload).to have_attributes(status: "pending", wa_message_id: "wamid.ENVIADA1")
    end

    it "no upload da mídia (que não envia nada ao contato), tenta de novo mesmo sem confirmação" do
      message = outbound(kind: "image", body: nil, media_mime_type: "image/jpeg", media_filename: "foto.jpg")
      message.media.attach(io: StringIO.new("jpeg"), filename: "foto.jpg", content_type: "image/jpeg")
      requests = stub_graph(Net::ReadTimeout, graph_response(200, { "id" => "MEDIA1" }), accepted)

      perform_enqueued_jobs { described_class.perform_later(message) }

      expect(requests.map { |r| r.path.split("/").last }).to eq(%w[media media messages])
      expect(message.reload).to have_attributes(media_id: "MEDIA1", wa_message_id: "wamid.ENVIADA1")
    end

    it "erro transitório da própria Meta no POST tenta de novo" do
      message = outbound(body: "Oi")
      stub_graph(graph_error(503, 2, "Service temporarily unavailable"))
      expect { described_class.perform_now(message) }.to have_enqueued_job(described_class)
      expect(message.reload.status).to eq("pending")
    end
  end

  it "não leva o corpo, o telefone nem o nome para o log do Active Job (os broadcasts levam só IDs)" do
    log = StringIO.new
    original = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::Logger.new(log)
    conversation.update!(profile_name: "Henrique Duarte")
    described_class.perform_later(outbound(body: "Proposta de R$ 12.000"))
    expect(log.string).to include("Enqueued WhatsappSendJob", "Enqueued Turbo::Streams::ActionBroadcastJob").and(exclude("12.000", "5511991023344", "Henrique"))
    expect(log.string[/Enqueued WhatsappSendJob.*$/]).not_to include("arguments")
  ensure
    ActiveJob::Base.logger = original
  end
end
