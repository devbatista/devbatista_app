module Mcp
  module Tools
    class AtualizarLead < Base
      include CommercialData

      tool_name "atualizar_lead"
      title "Atualizar lead"
      description <<~TEXT.squish
        Altera dados de um lead: só os campos enviados mudam; null limpa o campo. observacoes substitui o texto
        inteiro (para registrar uma conversa, prefira registrar_interacao). Para mudar o status use mover_lead,
        marcar_perdido ou converter_lead.
      TEXT
      writes
      input_schema(properties: { id: { type: "string" }, **LEAD_PROPERTIES }, required: [ "id" ], additionalProperties: false)

      def execute(id:, **fields)
        lead = authorize(Lead.find(id), :update?)
        fail!("Envie ao menos um campo para alterar.") if fields.empty?

        lead.update!(attributes_from(fields, LEAD_FIELDS))
        lead_details(lead)
      end
    end
  end
end
