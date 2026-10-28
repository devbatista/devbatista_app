require "rails_helper"

RSpec.describe "WhatsApp → Conversas" do
  let(:admin) { create(:user, :admin, name: "Rafael Batista") }
  let(:reader) { create(:user, role: create(:role, permissions: { "whatsapp" => "read" })) }
  let!(:account) { create(:whatsapp_account, status: "connected") }
  let(:now) { Time.zone.parse("2026-10-28 11:24") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  around { |example| travel_to(now) { example.run } }

  def conversation(**attributes)
    create(:whatsapp_conversation, account: account, last_message_at: 1.hour.ago, preview: "Oi", **attributes)
  end

  def message(conv, *traits, **attributes)
    create(:whatsapp_message, *traits, conversation: conv, sent_at: 30.minutes.ago, **attributes)
  end

  describe "lista" do
    before { sign_in admin }

    it "mostra só as conversas com mensagem, com filtros, busca e contagem" do
      lead = create(:lead, name: "Henrique Duarte", company_name: "Grupo Norte")
      conversation(profile_name: "Henrique", lead: lead, unread_count: 2, last_inbound_at: 1.hour.ago, preview: "Consegue incluir o módulo?")
      conversation(profile_name: "Juliana", contact: create(:contact, name: "Juliana Ferraz"), last_inbound_at: 2.days.ago)
      conversation(profile_name: "Lu", wa_id: nil, username: "lu.martins", last_message_at: 3.hours.ago)
      create(:whatsapp_conversation, account: account, saved_name: "Só na agenda", last_message_at: nil) # sincronização da agenda

      get whatsapp_conversations_path
      body = response.body
      expect(body).to include("Henrique", "Juliana", "Lu", "Grupo Norte", "@lu.martins", "Consegue incluir o módulo?", "Sem vínculo", "Cliente")
      expect(body).not_to include("Só na agenda")
      expect(body).to match(/Todas <span class="c">3/).and match(/Não lidas <span class="c">1/).and match(/Janela aberta <span class="c">1/)
      expect(body).to include('channel="WhatsappStreamsChannel"', %(id="#{ActionView::RecordIdentifier.dom_id(account, :inbox)}"))

      get whatsapp_conversations_path(filtro: "leads"), headers: { "Turbo-Frame" => "whatsapp_inbox" }
      expect(response.body).to include("Henrique").and(exclude("Juliana"))
      get whatsapp_conversations_path(filtro: "sem-vinculo"), headers: { "Turbo-Frame" => "whatsapp_inbox" }
      expect(response.body).to include("Lu").and(exclude("Henrique"))
      get whatsapp_conversations_path(filtro: "janela"), headers: { "Turbo-Frame" => "whatsapp_inbox" }
      expect(response.body).to include("Henrique").and(exclude("Juliana"))
      get whatsapp_conversations_path(q: "lu.mar"), headers: { "Turbo-Frame" => "whatsapp_inbox" }
      expect(response.body).to include("Lu").and(exclude("Henrique"))
      get whatsapp_conversations_path(q: "99102"), headers: { "Turbo-Frame" => "whatsapp_inbox" }
      expect(response.body).to include("Nenhuma conversa")
    end

    it "pagina pela última mensagem, sem repetir" do
      stub_const("WhatsappConversationsController::INBOX_PAGE", 2)
      %w[A B C].each_with_index { |name, i| conversation(profile_name: "Pessoa #{name}", last_message_at: (i + 1).hours.ago) }

      get whatsapp_conversations_path
      expect(response.body).to include("Pessoa A", "Pessoa B", 'loading="lazy"').and(exclude("Pessoa C"))
      src = response.body[/src="([^"]*cursor_id[^"]*)"/, 1]
      get CGI.unescapeHTML(src)
      expect(response.body).to include("Pessoa C").and(exclude("Pessoa A"))
    end
  end

  describe "conversa aberta" do
    before { sign_in admin }

    it "zera as não lidas, enfileira a leitura na Meta e mostra a linha do tempo" do
      conv = conversation(profile_name: "Henrique", wa_id: nil, bsuid: "BR.118034776612", unread_count: 2, last_inbound_at: 30.minutes.ago)
      message(conv, body: "Bom dia! Veja https://exemplo.com/a?b=1&c=2. <script>alert(1)</script>", sent_at: 2.days.ago)
      reacted = message(conv, :outbound, body: "Confirmando terça às 10h.", user: admin, status: "read", sent_at: 1.hour.ago)
      create(:whatsapp_message, conversation: conv, kind: "reaction", body: nil, reaction_to_wa_message_id: reacted.wa_message_id, reaction_emoji: "👍")
      create(:whatsapp_message, conversation: conv, kind: "reaction", body: nil, reaction_to_wa_message_id: reacted.wa_message_id, reaction_emoji: "", origin: "contact")
      message(conv, body: "Ok!", reply_to_wa_message_id: reacted.wa_message_id, sent_at: 40.minutes.ago)
      message(conv, :outbound, origin: "phone", user: nil, body: "Enviada do celular", from_history: true, sent_at: 35.minutes.ago)
      message(conv, kind: "image", body: "Fluxo atual", media_id: "123", media_mime_type: "image/jpeg")
      message(conv, body: "apagada", revoked_at: 1.minute.ago, sent_at: 20.minutes.ago)
      message(conv, :outbound, kind: "template", template_name: "lembrete_proposta", template_language: "pt_BR", body: "Olá, Beatriz.",
                               status: "failed", error_code: "131026", error_message: "A mensagem não pôde ser entregue a esse contato.", sent_at: 10.minutes.ago)
      conv.messages.inbound.update_all(wa_message_id: nil)
      inbound = message(conv, body: "Última", sent_at: 5.minutes.ago)

      expect { get whatsapp_conversation_path(conv) }.to have_enqueued_job(WhatsappReadJob).with(conv)

      expect(conv.reload.unread_count).to eq(0)
      body = response.body
      expect(body).to include("Henrique", "telefone não compartilhado", "BR.118034776612", "Janela aberta · fecha em 23h", "26/10/2026", "Hoje")
      expect(body).to include(%(<a href="https://exemplo.com/a?b=1&amp;c=2" rel="noopener noreferrer" target="_blank">https://exemplo.com/a?b=1&amp;c=2</a>.))
      expect(body).to include("&lt;script&gt;alert(1)&lt;/script&gt;").and(exclude("<script>alert(1)"))
      expect(body).to include("Rafael Batista", "pelo Admin", "Lida", "👍", "Celular", "Histórico", "Imagem: baixando…", "Mensagem apagada",
                              "Template · lembrete_proposta", "A mensagem não pôde ser entregue a esse contato. (erro 131026)", "Tentar de novo")
      expect(body).to include(%(class="quote" href="##{ActionView::RecordIdentifier.dom_id(reacted)}"))
      expect(body).to include(%(data-reply-id="#{inbound.wa_message_id}"))
      expect(body.scan(%(class="reactions")).size).to eq(1)
      expect(body).not_to include("apagada</p>")
    end

    it "carrega as mensagens anteriores por cursor, sem pular nem repetir" do
      stub_const("WhatsappConversationsController::THREAD_PAGE", 2)
      conv = conversation
      %w[primeira segunda terceira].each_with_index { |text, i| message(conv, body: "msg #{text}", sent_at: (3 - i).minutes.ago) }

      get whatsapp_conversation_path(conv)
      expect(response.body).to include("msg segunda", "msg terceira").and(exclude("msg primeira"))
      src = response.body[/src="([^"]*messages\?before=[^"]*)"/, 1]
      message(conv, body: "msg nova", sent_at: Time.current) # chegou depois: não entra na página anterior
      get CGI.unescapeHTML(src)
      expect(response.body).to include("msg primeira").and(exclude("msg segunda", "msg nova"))
    end

    it "abre só a conversa quando vem da lista (turbo-frame)" do
      conv = conversation(profile_name: "Henrique")
      get whatsapp_conversation_path(conv), headers: { "Turbo-Frame" => "whatsapp_conversation" }
      expect(response.body).to include('<turbo-frame id="whatsapp_conversation">', "Henrique").and(exclude("Lista de conversas"))
    end

    it "marca como lida a mensagem que chega com a conversa aberta" do
      conv = conversation(unread_count: 1)
      message(conv)
      expect { post read_whatsapp_conversation_path(conv) }.to have_enqueued_job(WhatsappReadJob)
      expect(response).to have_http_status(:no_content)
      expect(conv.reload.unread_count).to eq(0)
    end

    it "deixa só leitura a conversa de conta desconectada ou com o token vencido" do
      conv = conversation(last_inbound_at: 1.hour.ago)
      account.update!(status: "reconnect_required")
      get whatsapp_conversation_path(conv)
      expect(response.body).to include("Conversa só para leitura.", "O acesso à Meta venceu", "Integrações → WhatsApp").and(exclude('name="body"'))
    end
  end

  describe "envio" do
    let(:conv) { conversation(last_inbound_at: 1.hour.ago) }

    before { sign_in admin }

    it "envia texto com a janela aberta: grava Enviando, enfileira o job e devolve o balão" do
      reply = message(conv, body: "Pode ser terça?")
      expect { post whatsapp_conversation_whatsapp_messages_path(conv), params: { body: "Pode sim!", reply_to: reply.wa_message_id }, headers: turbo }
        .to have_enqueued_job(WhatsappSendJob)

      sent = conv.messages.outbound.sole
      expect(sent).to have_attributes(kind: "text", body: "Pode sim!", status: "pending", origin: "admin", user: admin, reply_to_wa_message_id: reply.wa_message_id)
      expect(conv.reload).to have_attributes(preview: "Pode sim!", last_message_at: now)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(action="append" target="#{ActionView::RecordIdentifier.dom_id(conv, :thread)}"), "Enviando", "Pode sim!")
      expect(response.body).to include(%(action="replace" target="#{ActionView::RecordIdentifier.dom_id(conv, :composer)}"))
    end

    it "envia mídia com legenda, conferindo o tipo e o tamanho" do
      photo = Rack::Test::UploadedFile.new(StringIO.new("jpeg"), "image/jpeg", original_filename: "fluxo.jpg")
      post whatsapp_conversation_whatsapp_messages_path(conv), params: { body: "O fluxo", file: photo }, headers: turbo

      sent = conv.messages.outbound.sole
      expect(sent).to have_attributes(kind: "image", body: "O fluxo", media_mime_type: "image/jpeg", media_filename: "fluxo.jpg")
      expect(sent.media.download).to eq("jpeg")

      audio = Rack::Test::UploadedFile.new(StringIO.new("ogg"), "audio/ogg", original_filename: "nota.ogg")
      post whatsapp_conversation_whatsapp_messages_path(conv), params: { body: "sem legenda no áudio", file: audio }, headers: turbo
      expect(conv.messages.outbound.find_by(kind: "audio").body).to be_nil

      zip = Rack::Test::UploadedFile.new(StringIO.new("zip"), "application/zip", original_filename: "x.zip")
      post whatsapp_conversation_whatsapp_messages_path(conv), params: { file: zip }, headers: turbo
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("O WhatsApp não aceita esse tipo de arquivo (application/zip).")

      stub_const("Whatsapp::Client::MEDIA_LIMITS", Whatsapp::Client::MEDIA_LIMITS.merge("image" => 2))
      post whatsapp_conversation_whatsapp_messages_path(conv), params: { file: Rack::Test::UploadedFile.new(StringIO.new("jpeg"), "image/jpeg", original_filename: "grande.jpg") }, headers: turbo
      expect(response.body).to include("passa do limite")
      expect(conv.messages.outbound.count).to eq(2)
    end

    it "recusa texto com a janela fechada e qualquer envio com a conta desconectada, mantendo o texto" do
      conv.update!(last_inbound_at: 2.days.ago)
      expect { post whatsapp_conversation_whatsapp_messages_path(conv), params: { body: "Oi" }, headers: turbo }.not_to have_enqueued_job
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("A janela de 24h está fechada. Envie um template aprovado.", "Oi</textarea>")

      conv.update!(last_inbound_at: 1.hour.ago)
      account.update!(status: "disconnected")
      post whatsapp_conversation_whatsapp_messages_path(conv), params: { body: "Oi" }, headers: turbo
      expect(response.body).to include("O número está desconectado")
      expect(conv.messages.count).to eq(0)
    end

    it "aceita template com a janela fechada, com as variáveis, o cabeçalho de mídia e o botão" do
      conv.update!(last_inbound_at: 2.days.ago)
      template = create(:whatsapp_template, account: account, name: "lembrete_proposta", status: "approved", components: [
        { "type" => "HEADER", "format" => "DOCUMENT", "example" => { "header_handle" => [ "h" ] } },
        { "type" => "BODY", "text" => "Olá, {{1}}. A proposta {{2}} vence amanhã." },
        { "type" => "BUTTONS", "buttons" => [ { "type" => "URL", "text" => "Ver proposta", "url" => "https://admin.devbatista.com/p/{{1}}" } ] }
      ])
      pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF"), "application/pdf", original_filename: "proposta.pdf")

      get whatsapp_conversation_path(conv)
      expect(response.body).to include("Responder com template", "lembrete_proposta · Utilidade · Português (BR)")

      expect do
        post whatsapp_conversation_whatsapp_messages_path(conv), headers: turbo, params: {
          kind: "template", template_id: template.id, header_file: pdf, values: { body: [ "Beatriz", "Novo site" ], buttons: { "0" => "p/P-2026-029" } }
        }
      end.to have_enqueued_job(WhatsappSendJob)

      sent = conv.messages.outbound.sole
      expect(sent).to have_attributes(kind: "template", template_name: "lembrete_proposta", body: "Olá, Beatriz. A proposta Novo site vence amanhã.",
                                      template_params: { "body" => [ "Beatriz", "Novo site" ], "header" => [], "buttons" => { "0" => "p/P-2026-029" }, "header_media" => "document" })
      expect(sent.media.filename.to_s).to eq("proposta.pdf")

      post whatsapp_conversation_whatsapp_messages_path(conv), headers: turbo, params: { kind: "template", template_id: template.id, values: { body: [ "Beatriz" ] } }
      expect(response.body).to include("Preencha todas as variáveis do template.")
    end

    it "tenta de novo a mensagem que falhou como mensagem nova" do
      failed = message(conv, :outbound, body: "Confirmado", status: "failed", error_code: "131026", user: admin)
      expect { post retry_whatsapp_message_path(failed), headers: turbo }.to have_enqueued_job(WhatsappSendJob)
      expect(conv.messages.outbound.where(body: "Confirmado").pluck(:status)).to contain_exactly("failed", "pending")
      expect(failed.reload.wa_message_id).to be_present
    end
  end

  describe "mídia" do
    let(:conv) { conversation }
    let(:photo) { message(conv, kind: "image", media_id: "1").tap { |m| m.media.attach(io: StringIO.new("jpeg"), filename: "foto.jpg", content_type: "image/jpeg") } }

    it "abre só com permissão, por uma URL temporária do serviço" do
      sign_in reader
      get media_whatsapp_message_path(photo)
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/rails/active_storage/disk/")

      sign_in create(:user, :comercial)
      get media_whatsapp_message_path(photo)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "permissões" do
    let(:conv) { conversation(last_inbound_at: 1.hour.ago) }

    it "deixa quem só lê ver as conversas sem enviar, e barra quem não tem a área" do
      sign_in reader
      get whatsapp_conversation_path(conv)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('class="wa show-conv can-send"')

      post whatsapp_conversation_whatsapp_messages_path(conv), params: { body: "Oi" }, headers: turbo
      expect(response).to have_http_status(:forbidden)
      expect(conv.messages.count).to eq(0)

      sign_in create(:user, :comercial)
      get whatsapp_conversations_path
      expect(response).to have_http_status(:forbidden)
    end
  end
end
