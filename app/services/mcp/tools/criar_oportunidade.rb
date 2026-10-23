module Mcp
  module Tools
    class CriarOportunidade < Base
      include CommercialData

      tool_name "criar_oportunidade"
      title "Criar oportunidade"
      description <<~TEXT.squish
        Cria uma oportunidade para uma empresa já cadastrada (buscar_empresas). Para lead que ainda não é empresa,
        use converter_lead. A probabilidade, se não vier, é a sugerida pela etapa (Reunião 25%, Proposta 50%,
        Negociação 75%).
      TEXT
      writes
      input_schema(
        properties: {
          **OPPORTUNITY_PROPERTIES,
          etapa: { type: "string", enum: Opportunity::OPEN_STAGES, description: "Padrão: meeting" },
          lead_id: { type: "string", description: "Lead de origem, se houver" }
        },
        required: %w[titulo empresa_id], additionalProperties: false
      )

      def execute(etapa: "meeting", lead_id: nil, **fields)
        attrs = attributes_from(fields, OPPORTUNITY_FIELDS).merge(stage: etapa, lead_id: lead_id)
        attrs[:user_id] ||= user.id
        opportunity = authorize(Opportunity.new(attrs), :create?)
        opportunity.save!

        opportunity_details(opportunity)
      end
    end
  end
end
