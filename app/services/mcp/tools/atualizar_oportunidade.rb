module Mcp
  module Tools
    class AtualizarOportunidade < Base
      include CommercialData

      tool_name "atualizar_oportunidade"
      title "Atualizar oportunidade"
      description <<~TEXT.squish
        Altera dados de uma oportunidade (valor, probabilidade, previsão, próximo passo etc.): só os campos enviados
        mudam; null limpa o campo. Para mudar a etapa use mover_oportunidade ou marcar_perdido.
      TEXT
      writes
      input_schema(properties: { id: { type: "string" }, **OPPORTUNITY_PROPERTIES }, required: [ "id" ], additionalProperties: false)

      def execute(id:, **fields)
        opportunity = authorize(Opportunity.find(id), :update?)
        fail!("Envie ao menos um campo para alterar.") if fields.empty?

        opportunity.update!(attributes_from(fields, OPPORTUNITY_FIELDS))
        opportunity_details(opportunity)
      end
    end
  end
end
