module Mcp
  module Tools
    class BuscarOportunidades < Base
      include CommercialData

      tool_name "buscar_oportunidades"
      title "Buscar oportunidades"
      description <<~TEXT.squish
        Lista oportunidades (negócios em andamento com empresas), das que fecham antes para as que fecham depois.
        Filtra por termo no título, etapa, empresa e responsável. Use ver_oportunidade para o histórico.
      TEXT
      read_only
      input_schema(
        properties: {
          termo: { type: "string", description: "Parte do título" },
          etapa: { type: "array", items: { type: "string", enum: Opportunity::STAGE_LABELS.keys }, description: "Uma ou mais etapas" },
          empresa_id: { type: "string", description: "Id da empresa (ver buscar_empresas)" },
          responsavel_id: { type: "string", description: "Id do usuário responsável" },
          so_abertas: { type: "boolean", description: "Só Reunião, Proposta e Negociação" },
          **PAGINATION
        },
        additionalProperties: false
      )

      def execute(termo: nil, etapa: nil, empresa_id: nil, responsavel_id: nil, so_abertas: false, pagina: nil, por_pagina: nil)
        authorize(Opportunity, :index?)
        scope = policy_scope(Opportunity).includes(:company, :service, :user)
                                         .order(Arel.sql("expected_close_on ASC NULLS LAST"), created_at: :desc)
        scope = scope.search(termo) if termo.present?
        scope = scope.where(stage: etapa) if etapa.present?
        scope = scope.where(company_id: empresa_id) if empresa_id.present?
        scope = scope.where(user_id: responsavel_id) if responsavel_id.present?
        scope = scope.open if so_abertas
        opportunities, pager = paginate(scope, pagina, por_pagina)

        { oportunidades: opportunities.map { |opportunity| opportunity_data(opportunity) }, paginacao: pager }
      end
    end
  end
end
