# Conversa do WhatsApp de um lead (docs/specs/mcp-comercial/README.md): as mensagens das conversas
# ligadas a ele, recebidas e enviadas (pelo Admin ou pelo app do celular), em ordem cronológica, e a
# janela de 24h. Só leitura e exige leitura na área WhatsApp, como a tela das conversas.
#
# São as `limite` mensagens mais recentes (a partir de `desde`, se vier), devolvidas da mais antiga
# para a mais nova; `omitidas` conta as anteriores que ficaram de fora. Reações não entram.
module Mcp
  module Tools
    class VerConversaWhatsapp < Base
      include WhatsappData

      LIMIT = 30
      MAX_LIMIT = 100

      tool_name "ver_conversa_whatsapp"
      title "Ver conversa do WhatsApp"
      description <<~TEXT.squish
        Mensagens do WhatsApp de um lead, em ordem cronológica: direção (recebida ou enviada), horário, texto
        (mídia entre colchetes, como "[áudio]" ou "[imagem] legenda") e se a janela de 24h para mensagem livre está
        aberta e até quando. Traz as mais recentes; use desde para começar num dia. Para achar quem respondeu, use
        buscar_leads com com_resposta_whatsapp_desde.
      TEXT
      read_only
      input_schema(
        properties: {
          lead_id: { type: "string", description: "Id do lead (UUID)" },
          desde: { type: "string", format: "date", description: "Só as mensagens a partir deste dia, AAAA-MM-DD" },
          limite: { type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "Quantas mensagens, as mais recentes (padrão #{LIMIT})" }
        },
        required: [ "lead_id" ], additionalProperties: false
      )

      def execute(lead_id:, desde: nil, limite: nil)
        lead = authorize(Lead.find(lead_id))
        authorize(WhatsappConversation, :index?)
        since = parse_day(desde, "desde") if desde.present?

        conversations = policy_scope(WhatsappConversation).with_messages.where(lead: lead).includes(:account)
                                                          .order(last_message_at: :desc).to_a
        return no_conversation(lead) if conversations.empty?

        scope = WhatsappMessage.timeline.where(conversation: conversations)
        scope = scope.where(sent_at: since.in_time_zone.beginning_of_day..) if since
        total = scope.count
        messages = scope.includes(:user).reorder(sent_at: :desc, id: :desc).limit((limite || LIMIT).clamp(1, MAX_LIMIT)).to_a.reverse

        { lead: lead_ref(lead), **window(conversations), conversas: conversations.map { |conversation| conversation_ref(conversation) },
          mensagens: messages.map { |message| message_data(message) }, total: total, omitidas: total - messages.size }
      end

      private

      # A janela vale pela conversa que recebeu por último (é por ela que enviar_whatsapp responde).
      def window(conversations)
        latest = conversations.select(&:last_inbound_at).max_by(&:last_inbound_at)
        { janela_aberta: latest&.window_open? || false, janela_fecha_em: (latest.window_closes_at.iso8601 if latest&.window_open?),
          ultima_recebida_em: latest&.last_inbound_at&.iso8601 }
      end

      def no_conversation(lead)
        { lead: lead_ref(lead), janela_aberta: false, janela_fecha_em: nil, ultima_recebida_em: nil, conversas: [],
          mensagens: [], total: 0, omitidas: 0, aviso: no_conversation_notice(lead) }
      end

      def no_conversation_notice(lead)
        wa_ids = Whatsapp::Phone.wa_ids(lead.whatsapp)
        if wa_ids.any? && policy_scope(WhatsappConversation).with_messages.unlinked.exists?(wa_id: wa_ids)
          "Há uma conversa com o número #{lead.whatsapp} ainda sem vínculo. Ligue a conversa a este lead na tela do WhatsApp para lê-la aqui."
        elsif lead.whatsapp.blank?
          "O lead não tem WhatsApp cadastrado e não há conversa ligada a ele."
        else
          "Ainda não há conversa de WhatsApp com este lead."
        end
      end

      def conversation_ref(conversation)
        { id: conversation.id, numero: conversation.phone_label, conta: conversation.account.to_s,
          link: link(:whatsapp_conversation, conversation) }
      end

      def lead_ref(lead)
        { id: lead.id, nome: lead.name, whatsapp: lead.whatsapp, link: link(:lead, lead) }
      end
    end
  end
end
