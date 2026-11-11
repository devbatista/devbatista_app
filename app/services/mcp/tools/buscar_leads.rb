module Mcp
  module Tools
    class BuscarLeads < Base
      include CommercialData
      include WhatsappData

      tool_name "buscar_leads"
      title "Buscar leads"
      description <<~TEXT.squish
        Lista leads do Comercial, dos mais recentes para os mais antigos. Filtra por termo (nome, empresa
        ou e-mail), status, origem e responsável. Com com_resposta_whatsapp_desde, só os leads que mandaram
        mensagem no WhatsApp a partir do dia, com a última mensagem recebida. Use ver_lead para o histórico
        completo de um lead e ver_conversa_whatsapp para a conversa.
      TEXT
      read_only
      input_schema(
        properties: {
          termo: { type: "string", description: "Parte do nome, da empresa ou do e-mail" },
          status: { type: "array", items: { type: "string", enum: Lead::STATUS_LABELS.keys }, description: "Um ou mais status" },
          origem: { type: "string", enum: Lead::ORIGIN_LABELS.keys },
          responsavel_id: { type: "string", description: "Id do usuário responsável (ver opcoes_comerciais)" },
          so_abertos: { type: "boolean", description: "Só Novo Lead, Contato Realizado e Qualificado" },
          com_resposta_whatsapp_desde: { type: "string", format: "date",
                                         description: "AAAA-MM-DD: só os leads que mandaram mensagem no WhatsApp a partir deste dia" },
          **PAGINATION
        },
        additionalProperties: false
      )

      def execute(termo: nil, status: nil, origem: nil, responsavel_id: nil, so_abertos: false, com_resposta_whatsapp_desde: nil,
                  pagina: nil, por_pagina: nil)
        authorize(Lead, :index?)
        scope = policy_scope(Lead).includes(:service, :user).order(entered_on: :desc, created_at: :desc)
        scope = scope.search(termo) if termo.present?
        scope = scope.where(status: status) if status.present?
        scope = scope.where(origin: origem) if origem
        scope = scope.where(user_id: responsavel_id) if responsavel_id.present?
        scope = scope.open if so_abertos
        replies = whatsapp_replies(com_resposta_whatsapp_desde) if com_resposta_whatsapp_desde.present?
        scope = scope.where(id: replies.select("whatsapp_conversations.lead_id")) if replies
        leads, pager = paginate(scope, pagina, por_pagina)

        summaries = replies ? reply_summaries(replies, leads.map(&:id)) : {}
        { leads: leads.map { |lead| lead_data(lead).merge(summaries.fetch(lead.id, {})) }, paginacao: pager }
      end

      private

      # Mensagens recebidas a partir do dia, nas conversas ligadas a um lead que o usuário pode ler.
      def whatsapp_replies(value)
        authorize(WhatsappConversation, :index?)
        conversations = policy_scope(WhatsappConversation).where.not(lead_id: nil)
        replies_since(parse_day(value, "com_resposta_whatsapp_desde")).joins(:conversation).merge(conversations)
      end

      # Quantas mensagens cada lead da página mandou no período e a última delas.
      def reply_summaries(replies, lead_ids)
        replies = replies.where(whatsapp_conversations: { lead_id: lead_ids })
        counts = replies.group("whatsapp_conversations.lead_id").count
        latest = replies.select("DISTINCT ON (whatsapp_conversations.lead_id) whatsapp_messages.*, whatsapp_conversations.lead_id AS replied_lead_id")
                        .reorder(Arel.sql("whatsapp_conversations.lead_id, whatsapp_messages.sent_at DESC, whatsapp_messages.id DESC"))
        latest.to_h do |message|
          [ message.replied_lead_id, { respostas_whatsapp: counts[message.replied_lead_id],
                                       ultima_resposta_whatsapp: { horario: message.sent_at.iso8601, texto: message_text(message) } } ]
        end
      end
    end
  end
end
