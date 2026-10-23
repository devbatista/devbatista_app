module Mcp
  module Tools
    # Mesmo movimento do quadro do pipeline (PipelineMoves): só entre as etapas de lead.
    class MoverLead < Base
      include CommercialData

      tool_name "mover_lead"
      title "Mover lead no pipeline"
      description <<~TEXT.squish
        Muda o status de um lead em aberto entre Novo Lead (new), Contato Realizado (contacted) e Qualificado
        (qualified). Para seguir adiante use converter_lead; para encerrar, marcar_perdido.
      TEXT
      writes
      input_schema(
        properties: { id: { type: "string" }, status: { type: "string", enum: Lead::OPEN_STATUSES } },
        required: %w[id status], additionalProperties: false
      )

      def execute(id:, status:)
        lead = authorize(Lead.find(id), :update?)
        fail!("O lead está #{lead.status_label.downcase} e não pode mais mudar de etapa.") unless lead.open?

        lead.update!(status: status)
        lead_data(lead)
      end
    end
  end
end
