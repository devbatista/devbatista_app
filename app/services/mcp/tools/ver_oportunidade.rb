module Mcp
  module Tools
    class VerOportunidade < Base
      include CommercialData

      tool_name "ver_oportunidade"
      title "Ver oportunidade"
      description "Ficha completa de uma oportunidade: dados, observações, interações registradas e propostas."
      read_only
      input_schema(properties: { id: { type: "string", description: "Id da oportunidade" } }, required: [ "id" ], additionalProperties: false)

      def execute(id:)
        opportunity = authorize(Opportunity.find(id))

        opportunity_details(opportunity).merge(
          interacoes: opportunity.interactions.includes(:user).recent.limit(30).map { |interaction| interaction_data(interaction) },
          propostas: opportunity.proposals.includes(:user, :company).order(created_at: :desc).map { |proposal| proposal_data(proposal) }
        )
      end
    end
  end
end
