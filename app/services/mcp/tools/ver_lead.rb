module Mcp
  module Tools
    class VerLead < Base
      include CommercialData

      tool_name "ver_lead"
      title "Ver lead"
      description <<~TEXT.squish
        Ficha completa de um lead: dados, observações, interações registradas, oportunidades e propostas.
      TEXT
      read_only
      input_schema(properties: { id: { type: "string", description: "Id do lead" } }, required: [ "id" ], additionalProperties: false)

      def execute(id:)
        lead = authorize(Lead.find(id))

        lead_details(lead).merge(
          interacoes: lead.interactions.includes(:user).recent.limit(30).map { |interaction| interaction_data(interaction) },
          oportunidades: lead.opportunities.includes(:company, :service, :user).map { |opportunity| opportunity_data(opportunity) },
          propostas: lead.proposals.includes(:user, :company).order(created_at: :desc).map { |proposal| proposal_data(proposal) }
        )
      end
    end
  end
end
