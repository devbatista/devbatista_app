module Mcp
  module Tools
    # Saída "Perdido" do pipeline (Losable), para lead ou oportunidade em aberto.
    class MarcarPerdido < Base
      include CommercialData

      tool_name "marcar_perdido"
      title "Marcar como perdido"
      description <<~TEXT.squish
        Marca um lead ou uma oportunidade em aberto como Perdido. O motivo tem de ser um dos motivos de perda
        de opcoes_comerciais; detalhes é texto livre. Só faça isso quando o usuário pedir.
      TEXT
      writes
      input_schema(
        properties: {
          tipo: { type: "string", enum: %w[lead oportunidade] },
          id: { type: "string" },
          motivo: { type: "string", description: "Um dos motivos_perda de opcoes_comerciais" },
          detalhes: { type: "string" }
        },
        required: %w[tipo id motivo], additionalProperties: false
      )

      def execute(tipo:, id:, motivo:, detalhes: nil)
        record = authorize((tipo == "lead" ? Lead : Opportunity).find(id), :update?)
        fail!("Só registros em aberto podem ser marcados como perdidos.") unless record.open?

        record.mark_lost!(reason: motivo, details: detalhes)
        record.is_a?(Lead) ? lead_details(record) : opportunity_details(record)
      end
    end
  end
end
