require "rails_helper"

# Nenhum teste fala com a Meta: stub_graph troca o Net::HTTP, e chamada sem resposta prevista falha.
RSpec.describe Mcp::Tools::EnviarWhatsapp do
  let(:admin) { create(:user) }
  let(:account) { create(:whatsapp_account, status: "connected") }
  let(:lead) { create(:lead, name: "Henrique Duarte", whatsapp: "(11) 99102-3344", status: "contacted") }
  let!(:conversation) do
    create(:whatsapp_conversation, account: account, wa_id: "5511991023344", bsuid: "BR.118034776612",
                                   last_inbound_at: 3.hours.ago, last_message_at: 3.hours.ago)
  end
  let(:texto) { "Oi, Henrique! Consigo te ligar amanhã às 10h?" }

  def accepted(wamid = "wamid.ENVIADA1")
    graph_response(200, { "messaging_product" => "whatsapp",
                          "contacts" => [ { "input" => "5511991023344", "wa_id" => "5511991023344", "user_id" => "BR.118034776612" } ],
                          "messages" => [ { "id" => wamid, "message_status" => "accepted" } ] })
  end

  def error_text(user = admin, **args)
    response = call_tool(described_class, user, lead_id: lead.id, texto: texto, **args)
    expect(response).to be_error
    response.content.dig(0, :text)
  end

  def outbound_messages
    conversation.messages.outbound
  end

  it "pede aprovação: destrutiva, de mundo aberto, não idempotente e com o título que avisa" do
    expect(described_class.annotations.to_h).to eq(readOnlyHint: false, destructiveHint: true, idempotentHint: false,
                                                   openWorldHint: true, title: "Enviar WhatsApp (requer aprovação)")
    expect(described_class.title).to eq("Enviar WhatsApp (requer aprovação)")
    expect(described_class.description).to start_with("Envia mensagem real ao contato. Só use depois que o usuário aprovou " \
                                                      "o texto exato no chat; antes, use simular: true para mostrar a prévia.")
    expect(Mcp::Endpoint::TOOLS).to include(described_class)
  end

  context "com a janela de 24h aberta" do
    it "envia na hora, devolve o wamid e registra a mensagem, o vínculo e a interação com o texto" do
      requests = stub_graph(accepted)

      data = tool_data(described_class, admin, lead_id: lead.id, texto: "  #{texto}  ")

      expect(data).to include("enviado" => true, "wamid" => "wamid.ENVIADA1", "para" => "5511991023344")
      expect(Time.iso8601(data["enviado_em"])).to be_within(5.seconds).of(Time.current)
      body = json_body(requests.first)
      expect(requests.first.path).to end_with("/#{account.phone_number_id}/messages")
      expect(body).to include("to" => "5511991023344", "type" => "text")
      expect(body["text"]).to eq("body" => texto, "preview_url" => false)

      message = outbound_messages.sole
      expect(message).to have_attributes(wa_message_id: "wamid.ENVIADA1", body: texto, origin: "admin", user: admin, kind: "text")
      expect(conversation.reload).to have_attributes(lead: lead, linked_by: admin)
      interaction = lead.interactions.where(whatsapp_conversation_id: nil).sole
      expect(interaction).to have_attributes(kind: "whatsapp", user: admin, occurred_on: Date.current)
      expect(interaction.notes).to eq("WhatsApp enviado pelo Claude · wamid.ENVIADA1\n\n#{texto}")
      expect(data["interacao"]).to include("id" => interaction.id, "tipo" => "whatsapp")
      expect(WhatsappSendJob).not_to have_been_enqueued
    end

    it "acha a conversa com o número do lead sem o nono dígito e envia para a forma que a Meta usa" do
      lead.update!(whatsapp: "+55 11 9102-3344")
      stub_graph(accepted)

      data = tool_data(described_class, admin, lead_id: lead.id, texto: texto)
      expect(data).to include("enviado" => true, "para" => "5511991023344")
    end

    it "conta a mensagem recebida há pouco menos de 24h (inclusive resposta automática do contato)" do
      conversation.update!(last_inbound_at: 23.hours.ago + 59.minutes)
      stub_graph(accepted)

      expect(tool_data(described_class, admin, lead_id: lead.id, texto: texto)).to include("enviado" => true)
    end
  end

  context "com a janela de 24h fechada" do
    it "não envia e diz a data da última mensagem recebida" do
      last = Time.zone.local(2026, 11, 8, 14, 32)
      travel_to(last + 25.hours) do
        conversation.update!(last_inbound_at: last)
        stub_graph # nenhuma chamada à Meta

        expect(error_text).to eq("Fora da janela de 24h, precisa de template aprovado. Última mensagem recebida desse contato: 2026-11-08 14:32.")
      end
      expect(outbound_messages).to be_empty
      expect(lead.interactions).to be_empty
    end

    it "não envia para número que nunca falou com a DevBatista" do
      lead.update!(whatsapp: "(21) 98888-7777")
      stub_graph

      expect(error_text).to eq("Fora da janela de 24h, precisa de template aprovado. Nenhuma mensagem recebida desse número.")
      expect(WhatsappMessage.outbound).to be_empty
    end
  end

  context "com o lead que não pode receber" do
    before { stub_graph }

    it "recusa lead sem WhatsApp cadastrado" do
      lead.update!(whatsapp: nil)
      expect(error_text).to start_with("O lead não tem WhatsApp cadastrado.")
    end

    it "recusa WhatsApp inválido no cadastro" do
      lead.update!(whatsapp: "1234")
      expect(error_text).to start_with("O WhatsApp do lead (1234) não é um número válido.")
    end

    it "recusa lead perdido" do
      lead.update!(status: "lost", lost_reason: "Sem orçamento")
      expect(error_text).to start_with("O lead está como Perdido: não envio WhatsApp para lead perdido.")
      expect(outbound_messages).to be_empty
    end

    it "recusa lead convertido" do
      lead.update!(status: "converted")
      expect(error_text).to start_with("O lead já foi convertido")
    end

    it "recusa o número que está na conversa de outro lead" do
      conversation.link!(create(:lead, name: "Outra Pessoa"))
      expect(error_text).to start_with("O número +55 11 99102-3344 já está na conversa com Outra Pessoa.")
    end

    it "recusa sem número do WhatsApp conectado" do
      account.update!(status: "disconnected")
      expect(error_text).to start_with("Nenhum número do WhatsApp conectado.")
    end

    it "recusa quem não tem escrita no WhatsApp" do
      expect(error_text(create(:user, :comercial))).to eq("Sem permissão para esta ação.")
    end
  end

  context "com erro da Meta" do
    it "devolve o código e a mensagem da Meta, deixa a mensagem como Falhou e não registra interação" do
      stub_graph(graph_error(400, 131_026, "(#131026) Message undeliverable", details: "Message Undeliverable."))

      text = error_text
      expect(text).to eq("Não enviado. Erro da Meta (código 131026): A mensagem não pôde ser entregue a esse contato. " \
                         "Mensagem da Meta: (#131026) Message undeliverable")
      expect(outbound_messages.sole).to have_attributes(status: "failed", error_code: "131026", wa_message_id: nil)
      expect(lead.interactions).to be_empty
      expect(conversation.reload.lead).to be_nil
    end

    it "não tenta de novo sozinho no erro transitório" do
      stub_graph(graph_error(503, 131_000, "(#131000) Something went wrong", transient: true))

      expect(error_text).to start_with("Não enviado. Erro da Meta (código 131000)")
      expect(outbound_messages.sole.status).to eq("failed")
      expect(WhatsappSendJob).not_to have_been_enqueued
    end

    it "fecha a janela quando a Meta diz que ela já fechou (131047)" do
      stub_graph(graph_error(400, 131_047, "(#131047) Re-engagement message"))

      expect(error_text).to include("código 131047")
      expect(conversation.reload.window_open?).to be(false)
    end

    it "sem confirmação da Meta, avisa e bloqueia o reenvio do mesmo texto" do
      stub_graph(Net::ReadTimeout)
      expect(error_text).to eq(WhatsappSendJob::UNCERTAIN)

      stub_graph # o segundo pedido nem chega à Meta
      expect(error_text).to start_with("A mesma mensagem já foi enviada nesta conversa há menos de 2 minutos")
      expect(outbound_messages.count).to eq(1)
    end
  end

  describe "duplicidade" do
    it "recusa o mesmo texto para o mesmo lead por 2 minutos e libera depois, ou com outro texto" do
      stub_graph(accepted("wamid.1"), accepted("wamid.2"), accepted("wamid.3"))
      tool_data(described_class, admin, lead_id: lead.id, texto: texto)

      expect(error_text).to start_with("A mesma mensagem já foi enviada nesta conversa há menos de 2 minutos")
      expect(tool_data(described_class, admin, lead_id: lead.id, texto: "Outro texto")).to include("wamid" => "wamid.2")

      travel 2.minutes + 1.second
      expect(tool_data(described_class, admin, lead_id: lead.id, texto: texto)).to include("wamid" => "wamid.3")
      expect(outbound_messages.count).to eq(3)
    end

    it "não conta o envio que falhou de vez" do
      stub_graph(graph_error(400, 131_026, "(#131026) Message undeliverable"), accepted)
      error_text

      expect(tool_data(described_class, admin, lead_id: lead.id, texto: texto)).to include("enviado" => true)
    end
  end

  describe "simular" do
    it "mostra o que seria enviado, sem enviar nem gravar" do
      stub_graph

      data = tool_data(described_class, admin, lead_id: lead.id, texto: texto, simular: true)

      expect(data).to include("simulacao" => true, "pode_enviar" => true, "impedimentos" => [], "para" => "5511991023344",
                              "texto" => texto, "caracteres" => texto.length, "janela_aberta" => true,
                              "lead" => { "id" => lead.id, "nome" => "Henrique Duarte" })
      expect(Time.iso8601(data["ultima_recebida_em"])).to be_within(1.second).of(conversation.last_inbound_at)
      expect(Time.iso8601(data["janela_fecha_em"])).to be_within(1.second).of(conversation.window_closes_at)
      expect(WhatsappMessage.outbound).to be_empty
      expect(Interaction.count).to eq(0)
    end

    it "mostra os impedimentos em vez de dar erro" do
      conversation.update!(last_inbound_at: 2.days.ago)
      lead.update!(status: "lost", lost_reason: "Sem orçamento")
      stub_graph

      data = tool_data(described_class, admin, lead_id: lead.id, texto: texto, simular: true)

      expect(data).to include("pode_enviar" => false, "janela_aberta" => false)
      expect(data["impedimentos"]).to contain_exactly(start_with("O lead está como Perdido"), start_with("Fora da janela de 24h"))
    end

    it "avisa da duplicidade" do
      create(:whatsapp_message, :outbound, conversation: conversation, body: texto, user: admin)
      stub_graph

      data = tool_data(described_class, admin, lead_id: lead.id, texto: texto, simular: true)
      expect(data["impedimentos"]).to contain_exactly(start_with("A mesma mensagem já foi enviada"))
    end
  end
end
