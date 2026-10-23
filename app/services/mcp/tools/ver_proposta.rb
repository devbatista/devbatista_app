module Mcp
  module Tools
    class VerProposta < Base
      include CommercialData

      tool_name "ver_proposta"
      title "Ver proposta"
      description <<~TEXT.squish
        Proposta completa: itens com serviço, recorrência e preço, total, MRR, condições de pagamento,
        prazo de entrega, contato, validade e datas de envio, visualização e decisão.
      TEXT
      read_only
      input_schema(properties: { id: { type: "string", description: "Id da proposta" } }, required: [ "id" ], additionalProperties: false)

      def execute(id:)
        proposal = authorize(Proposal.includes(:contact, :user, :company, :lead, items: :service).find(id))
        proposal_details(proposal)
      end
    end
  end
end
