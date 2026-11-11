require "rails_helper"

RSpec.describe "Conversa do WhatsApp pelo MCP" do
  let(:admin) { create(:user, name: "Rafael") }
  let(:comercial) { create(:user, :comercial) } # sem a área WhatsApp
  let(:account) { create(:whatsapp_account) }
  let(:now) { Time.zone.local(2026, 11, 11, 15, 0) }

  around { |example| travel_to(now) { example.run } }

  def conversation_for(lead, last_inbound_at: nil, **attributes)
    create(:whatsapp_conversation, account: account, lead: lead, last_message_at: now - 1.minute,
                                   last_inbound_at: last_inbound_at, **attributes)
  end

  def message(conversation, at, *traits, **attributes)
    create(:whatsapp_message, *traits, conversation: conversation, sent_at: at, **attributes)
  end

  def error_text(tool, user, **args)
    response = call_tool(tool, user, **args)
    expect(response).to be_error
    response.content.dig(0, :text)
  end

  describe Mcp::Tools::VerConversaWhatsapp do
    let(:lead) { create(:lead, name: "Henrique Duarte", whatsapp: "(11) 99102-3344", status: "contacted") }

    it "é só leitura e está no servidor" do
      expect(described_class.annotations.to_h).to include(readOnlyHint: true, destructiveHint: false)
      expect(Mcp::Endpoint::TOOLS).to include(described_class)
    end

    context "com o lead sem conversa" do
      it "devolve a lista vazia, a janela fechada e o motivo" do
        data = tool_data(described_class, admin, lead_id: lead.id)

        expect(data).to include("mensagens" => [], "conversas" => [], "total" => 0, "janela_aberta" => false, "janela_fecha_em" => nil,
                                "aviso" => "Ainda não há conversa de WhatsApp com este lead.")
        expect(data["lead"]).to include("id" => lead.id, "nome" => "Henrique Duarte")
      end

      it "avisa quando há conversa com o número do lead ainda sem vínculo, sem mostrar as mensagens dela" do
        unlinked = conversation_for(nil, wa_id: "5511991023344") # criada antes do lead: não se liga sozinha
        message(unlinked, now - 1.hour, body: "Oi, é o Henrique")

        data = tool_data(described_class, admin, lead_id: lead.id)

        expect(data["mensagens"]).to eq([])
        expect(data["aviso"]).to include("conversa com o número (11) 99102-3344 ainda sem vínculo")
      end

      it "avisa quando o lead não tem WhatsApp" do
        lead.update!(whatsapp: nil)
        expect(tool_data(described_class, admin, lead_id: lead.id)["aviso"]).to eq("O lead não tem WhatsApp cadastrado e não há conversa ligada a ele.")
      end
    end

    context "com conversa" do
      let!(:conversation) { conversation_for(lead, last_inbound_at: now - 2.hours, wa_id: "5511991023344") }

      it "devolve as mensagens em ordem cronológica, com direção, origem e a janela de 24h" do
        enviada = message(conversation, now - 3.hours, direction: "outbound", origin: "admin", status: "read", user: admin, body: "Bom dia, Henrique!")
        message(conversation, now - 2.hours, body: "Bom dia! Pode ser amanhã?")
        message(conversation, now - 90.minutes, direction: "outbound", origin: "phone", status: "delivered", body: "Combinado, 10h.")
        message(conversation, now - 1.hour, kind: "reaction", body: nil, reaction_emoji: "👍", reaction_to_wa_message_id: enviada.wa_message_id)

        data = tool_data(described_class, admin, lead_id: lead.id)

        expect(data["mensagens"]).to match([
          { "direcao" => "enviada", "horario" => (now - 3.hours).iso8601, "tipo" => "text", "texto" => "Bom dia, Henrique!",
            "origem" => "admin", "enviada_por" => "Rafael", "status" => "Lida", "wamid" => enviada.wa_message_id },
          include("direcao" => "recebida", "texto" => "Bom dia! Pode ser amanhã?", "origem" => "contato", "horario" => (now - 2.hours).iso8601),
          include("direcao" => "enviada", "texto" => "Combinado, 10h.", "origem" => "celular", "status" => "Entregue")
        ])
        expect(data["mensagens"].second).not_to have_key("status")
        expect(data).to include("total" => 3, "omitidas" => 0, "janela_aberta" => true,
                                "janela_fecha_em" => (now + 22.hours).iso8601, "ultima_recebida_em" => (now - 2.hours).iso8601)
        expect(data["conversas"]).to match([ { "id" => conversation.id, "numero" => "+55 11 99102-3344", "conta" => account.to_s,
                                            "link" => end_with("/whatsapp/conversations/#{conversation.id}") } ])
      end

      it "marca a mídia entre colchetes, com a legenda e o nome do documento" do
        message(conversation, now - 50.minutes, kind: "audio", body: nil, media_id: "m1", media_mime_type: "audio/ogg")
        message(conversation, now - 40.minutes, kind: "image", body: "A fachada da loja", media_id: "m2")
        message(conversation, now - 30.minutes, kind: "document", body: nil, media_id: "m3", media_filename: "orcamento.pdf")
        message(conversation, now - 20.minutes, kind: "sticker", body: nil, media_id: "m4")
        message(conversation, now - 15.minutes, kind: "location", body: "Padaria Sol · Rua A, 10")
        message(conversation, now - 10.minutes, kind: "button", body: "Quero saber mais")
        message(conversation, now - 5.minutes, kind: "unsupported", body: nil)
        message(conversation, now - 4.minutes, body: "Ops", revoked_at: now - 3.minutes)
        message(conversation, now - 2.minutes, :outbound, kind: "template", template_name: "boas_vindas", template_language: "pt_BR",
                                                          body: "Olá, Henrique!")

        texts = tool_data(described_class, admin, lead_id: lead.id)["mensagens"].pluck("texto")

        expect(texts).to eq([ "[áudio]", "[imagem] A fachada da loja", "[documento: orcamento.pdf]", "[figurinha]",
                              "[localização] Padaria Sol · Rua A, 10", "Quero saber mais", "[mensagem não suportada]",
                              "[mensagem apagada]", "[template boas_vindas] Olá, Henrique!" ])
      end

      it "mostra a falha no envio e as mensagens do histórico" do
        message(conversation, now - 5.days, body: "Mensagem antiga", from_history: true)
        message(conversation, now - 1.hour, :outbound, status: "failed", error_message: "Fora da janela de 24h")

        mensagens = tool_data(described_class, admin, lead_id: lead.id)["mensagens"]

        expect(mensagens.first).to include("do_historico" => true)
        expect(mensagens.second).to include("status" => "Falhou", "erro" => "Fora da janela de 24h")
      end

      # Payload como o da Meta em produção (resposta automática do contato, na coexistência): sem conteúdo.
      it "explica a mensagem que a Meta não repassou à API (131060), em vez de 'não suportada'" do
        payload = { "id" => "wamid.INDISPONIVEL", "from" => "5511991023344", "timestamp" => (now - 1.hour).to_i.to_s, "type" => "unsupported",
                    "unsupported" => { "type" => "unknown", "raw_type" => "unknown" },
                    "errors" => [ { "code" => 131060, "title" => "This message is unavailable.",
                                    "error_data" => { "details" => "This message is currently unavailable." } } ] }
        conversation.messages.create!(Whatsapp::MessageAttributes.call(payload).merge(direction: "inbound", origin: "contact", status: "received"))
        message(conversation, now - 30.minutes, kind: "unsupported", body: nil)

        mensagens = tool_data(described_class, admin, lead_id: lead.id)["mensagens"]

        expect(mensagens.first).to include(
          "direcao" => "recebida", "tipo" => "unsupported", "erro" => "This message is currently unavailable.",
          "texto" => "[mensagem indisponível: a Meta não enviou o conteúdo à API (código 131060). Leia no app do WhatsApp Business]"
        )
        expect(mensagens.second).to include("texto" => "[mensagem não suportada]").and(exclude("erro"))
      end

      it "filtra desde o início do dia e limita às mais recentes, contando as omitidas" do
        message(conversation, Time.zone.local(2026, 11, 9, 23, 59), body: "anteontem")
        message(conversation, Time.zone.local(2026, 11, 10, 0, 1), body: "ontem cedo")
        message(conversation, Time.zone.local(2026, 11, 10, 18), body: "ontem à tarde")
        message(conversation, now - 1.hour, body: "hoje")

        data = tool_data(described_class, admin, lead_id: lead.id, desde: "2026-11-10")
        expect(data["mensagens"].pluck("texto")).to eq([ "ontem cedo", "ontem à tarde", "hoje" ])

        data = tool_data(described_class, admin, lead_id: lead.id, limite: 2)
        expect(data["mensagens"].pluck("texto")).to eq([ "ontem à tarde", "hoje" ])
        expect(data).to include("total" => 4, "omitidas" => 2)
      end

      it "mostra a janela fechada quando a última recebida passou de 24h" do
        conversation.update!(last_inbound_at: now - 30.hours)

        data = tool_data(described_class, admin, lead_id: lead.id)

        expect(data).to include("janela_aberta" => false, "janela_fecha_em" => nil, "ultima_recebida_em" => (now - 30.hours).iso8601)
      end

      it "recusa data inválida e quem não lê a área WhatsApp" do
        expect(error_text(described_class, admin, lead_id: lead.id, desde: "10/11/2026")).to start_with("Data inválida em desde")
        expect(error_text(described_class, comercial, lead_id: lead.id)).to eq("Sem permissão para esta ação.")
      end
    end
  end

  describe Mcp::Tools::BuscarLeads, "com com_resposta_whatsapp_desde" do
    let(:respondeu) { create(:lead, name: "Respondeu hoje") }
    let(:ontem) { create(:lead, name: "Respondeu ontem") }
    let(:so_enviada) { create(:lead, name: "Só recebeu") }
    let(:so_reacao) { create(:lead, name: "Só reagiu") }
    let(:sem_conversa) { create(:lead, name: "Sem conversa") }

    before do
      conversation = conversation_for(respondeu)
      message(conversation, now - 5.hours, body: "Primeira")
      message(conversation, now - 1.hour, kind: "audio", body: nil, media_id: "m1")
      message(conversation_for(ontem), now - 1.day, body: "Ontem")
      message(conversation_for(so_enviada), now - 1.hour, :outbound)
      reacted = conversation_for(so_reacao)
      enviada = message(reacted, now - 2.hours, :outbound)
      message(reacted, now - 1.hour, kind: "reaction", body: nil, reaction_emoji: "👍", reaction_to_wa_message_id: enviada.wa_message_id)
      message(conversation_for(nil), now - 1.hour, body: "Conversa sem vínculo")
      sem_conversa
    end

    it "lista só os leads que mandaram mensagem desde o dia, com a contagem e a última" do
      data = tool_data(described_class, admin, com_resposta_whatsapp_desde: "2026-11-11")

      expect(data["leads"].pluck("nome")).to eq([ "Respondeu hoje" ])
      expect(data["leads"].first).to include("respostas_whatsapp" => 2,
                                             "ultima_resposta_whatsapp" => { "horario" => (now - 1.hour).iso8601, "texto" => "[áudio]" })
      expect(data["paginacao"]).to include("total" => 1)

      nomes = tool_data(described_class, admin, com_resposta_whatsapp_desde: "2026-11-10")["leads"].pluck("nome")
      expect(nomes).to contain_exactly("Respondeu hoje", "Respondeu ontem")
    end

    it "combina com os outros filtros e deixa a busca sem o filtro como era" do
      expect(tool_data(described_class, admin, com_resposta_whatsapp_desde: "2026-11-10", termo: "ontem")["leads"].pluck("nome"))
        .to eq([ "Respondeu ontem" ])
      sem_filtro = tool_data(described_class, admin)["leads"]
      expect(sem_filtro.size).to eq(5)
      expect(sem_filtro.first.keys).not_to include("respostas_whatsapp")
    end

    it "recusa data inválida e quem não lê a área WhatsApp" do
      expect(error_text(described_class, admin, com_resposta_whatsapp_desde: "ontem")).to start_with("Data inválida em com_resposta_whatsapp_desde")
      expect(error_text(described_class, comercial, com_resposta_whatsapp_desde: "2026-11-11")).to eq("Sem permissão para esta ação.")
    end
  end
end
