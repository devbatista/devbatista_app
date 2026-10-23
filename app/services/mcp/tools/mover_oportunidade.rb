module Mcp
  module Tools
    # Mesmo movimento do quadro do pipeline (PipelineMoves). "Fechado" só registra a data e a
    # probabilidade de 100%: contrato e serviços contratados vêm da aprovação da proposta, pela tela.
    class MoverOportunidade < Base
      include CommercialData

      STAGES = Opportunity::OPEN_STAGES + %w[won]

      tool_name "mover_oportunidade"
      title "Mover oportunidade no pipeline"
      description <<~TEXT.squish
        Muda a etapa de uma oportunidade entre Reunião (meeting), Proposta (proposal), Negociação (negotiation) e
        Fechado (won). A probabilidade passa a ser a sugerida pela etapa. Só use won quando o usuário disser que o
        negócio fechou; isso não cria contrato (a aprovação da proposta, feita pela tela, cria). Para perdido, use
        marcar_perdido.
      TEXT
      writes
      input_schema(
        properties: { id: { type: "string" }, etapa: { type: "string", enum: STAGES } },
        required: %w[id etapa], additionalProperties: false
      )

      def execute(id:, etapa:)
        opportunity = authorize(Opportunity.find(id), :update?)
        fail!("A oportunidade está perdida e não pode mudar de etapa.") if opportunity.lost?

        opportunity.update!(stage: etapa)
        opportunity_details(opportunity)
      end
    end
  end
end
