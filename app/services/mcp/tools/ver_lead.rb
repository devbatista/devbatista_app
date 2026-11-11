module Mcp
  module Tools
    class VerLead < Base
      include CommercialData
      include WhatsappData

      # Mensagens do WhatsApp nas interações "Conversa do dia": as mais recentes do lead, somando os dias.
      WHATSAPP_MESSAGES = 30

      tool_name "ver_lead"
      title "Ver lead"
      description <<~TEXT.squish
        Ficha completa de um lead: dados, observações, interações registradas, oportunidades e propostas.
      TEXT
      read_only
      input_schema(properties: { id: { type: "string", description: "Id do lead" } }, required: [ "id" ], additionalProperties: false)

      # Com leitura na área WhatsApp: janela_whatsapp_aberta_ate no topo, quando a janela de 24h está
      # aberta, e as mensagens do dia em cada interação "Conversa do dia" (formato do ver_conversa_whatsapp).
      def execute(id:)
        lead = authorize(Lead.find(id))
        interactions = lead.interactions.includes(:user).recent.limit(30).to_a
        messages = daily_conversation_messages(interactions, WHATSAPP_MESSAGES)

        { janela_whatsapp_aberta_ate: whatsapp_window_end(lead) }.compact.merge(lead_details(lead)).merge(
          interacoes: interactions.map { |interaction| interaction_data(interaction).merge(messages.fetch(interaction.id, {})) },
          oportunidades: lead.opportunities.includes(:company, :service, :user).map { |opportunity| opportunity_data(opportunity) },
          propostas: lead.proposals.includes(:user, :company).order(created_at: :desc).map { |proposal| proposal_data(proposal) }
        )
      end

      private

      def whatsapp_window_end(lead)
        whatsapp_window(lead_conversations(lead))[:janela_fecha_em] if whatsapp_readable?
      end
    end
  end
end
