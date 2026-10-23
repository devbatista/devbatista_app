module Mcp
  module Tools
    # Conversão do lead em empresa, contato e oportunidade (LeadConversion, RF 8), com os
    # mesmos valores sugeridos da tela; o que vier na chamada prevalece.
    class ConverterLead < Base
      include CommercialData

      FIELDS = {
        empresa_id: :company_id, nome_fantasia: :trade_name, razao_social: :legal_name, cnpj: :cnpj,
        contato_nome: :contact_name, contato_cargo: :contact_position, contato_whatsapp: :contact_whatsapp,
        contato_email: :contact_email, titulo: :title, servico_id: :service_id, valor_estimado: :estimated_value,
        probabilidade: :probability, previsao_fechamento: :expected_close_on, etapa: :stage, responsavel_id: :user_id
      }.freeze

      tool_name "converter_lead"
      title "Converter lead em cliente"
      description <<~TEXT.squish
        Converte um lead em aberto em empresa (prospect), contato e oportunidade, e marca o lead como Convertido.
        Informe empresa_id para vincular a uma empresa já cadastrada (buscar_empresas); sem ela, a empresa nova
        exige CNPJ válido. Se o CNPJ já existir, vincula à empresa existente. Os demais campos vêm do lead quando
        não forem enviados: contato = pessoa do lead, título = serviço de interesse, valor = preço do serviço,
        etapa Reunião, fechamento em 30 dias.
      TEXT
      writes
      input_schema(
        properties: {
          id: { type: "string", description: "Id do lead" },
          empresa_id: { type: "string" },
          nome_fantasia: { type: "string" }, razao_social: { type: "string" },
          cnpj: { type: "string", description: "Com ou sem pontuação" },
          contato_nome: { type: "string" }, contato_cargo: { type: "string" },
          contato_whatsapp: { type: "string" }, contato_email: { type: "string" },
          titulo: { type: "string", description: "Título da oportunidade" },
          servico_id: { type: "string" },
          valor_estimado: { type: "number", minimum: 0, description: "Em reais" },
          probabilidade: { type: "integer", minimum: 0, maximum: 100 },
          previsao_fechamento: CommercialData::DATE,
          etapa: { type: "string", enum: Opportunity::OPEN_STAGES },
          responsavel_id: { type: "string" }
        },
        required: [ "id" ], additionalProperties: false
      )

      def execute(id:, **fields)
        lead = authorize(Lead.find(id), :update?)
        authorize(Company, :create?) if fields[:empresa_id].blank?
        fail!("O lead está #{lead.status_label.downcase}; só leads em aberto podem ser convertidos.") unless lead.open?

        conversion = LeadConversion.from(lead)
        conversion.assign_attributes(attributes_from(fields, FIELDS))
        fail!("Não foi possível converter: #{conversion.errors.full_messages.to_sentence}.") unless conversion.save

        { lead: lead_data(lead.reload), empresa: company_ref(conversion.company).merge(link: link(:company, conversion.company)),
          oportunidade: opportunity_data(conversion.opportunity) }
      end
    end
  end
end
