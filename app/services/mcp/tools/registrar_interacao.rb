module Mcp
  module Tools
    class RegistrarInteracao < Base
      include CommercialData

      tool_name "registrar_interacao"
      title "Registrar interação"
      description <<~TEXT.squish
        Registra uma interação (ligação, WhatsApp, e-mail, reunião ou nota) no histórico de um lead ou de uma
        oportunidade, em seu nome. Use para anotar conversas e combinados.
      TEXT
      writes
      input_schema(
        properties: {
          tipo_registro: { type: "string", enum: %w[lead oportunidade] },
          id: { type: "string", description: "Id do lead ou da oportunidade" },
          tipo: { type: "string", enum: Interaction::KIND_LABELS.keys },
          notas: { type: "string", description: "O que foi conversado ou combinado" },
          data: CommercialData::DATE.merge(description: "Quando aconteceu, AAAA-MM-DD; padrão: hoje")
        },
        required: %w[tipo_registro id tipo notas], additionalProperties: false
      )

      def execute(tipo_registro:, id:, tipo:, notas:, data: nil)
        subject = authorize((tipo_registro == "lead" ? Lead : Opportunity).find(id), :update?)
        interaction = authorize(subject.interactions.new(kind: tipo, notes: notas, occurred_on: data || Date.current, user: user), :create?)
        interaction.save!

        interaction_data(interaction).merge(registro: tipo_registro, registro_id: subject.id)
      end
    end
  end
end
