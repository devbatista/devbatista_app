module Mcp
  module Tools
    class BuscarLeads < Base
      include CommercialData

      tool_name "buscar_leads"
      title "Buscar leads"
      description <<~TEXT.squish
        Lista leads do Comercial, dos mais recentes para os mais antigos. Filtra por termo (nome, empresa
        ou e-mail), status, origem e responsável. Use ver_lead para o histórico completo de um lead.
      TEXT
      read_only
      input_schema(
        properties: {
          termo: { type: "string", description: "Parte do nome, da empresa ou do e-mail" },
          status: { type: "array", items: { type: "string", enum: Lead::STATUS_LABELS.keys }, description: "Um ou mais status" },
          origem: { type: "string", enum: Lead::ORIGIN_LABELS.keys },
          responsavel_id: { type: "string", description: "Id do usuário responsável (ver opcoes_comerciais)" },
          so_abertos: { type: "boolean", description: "Só Novo Lead, Contato Realizado e Qualificado" },
          **PAGINATION
        },
        additionalProperties: false
      )

      def execute(termo: nil, status: nil, origem: nil, responsavel_id: nil, so_abertos: false, pagina: nil, por_pagina: nil)
        authorize(Lead, :index?)
        scope = policy_scope(Lead).includes(:service, :user).order(entered_on: :desc, created_at: :desc)
        scope = scope.search(termo) if termo.present?
        scope = scope.where(status: status) if status.present?
        scope = scope.where(origin: origem) if origem
        scope = scope.where(user_id: responsavel_id) if responsavel_id.present?
        scope = scope.open if so_abertos
        leads, pager = paginate(scope, pagina, por_pagina)

        { leads: leads.map { |lead| lead_data(lead) }, paginacao: pager }
      end
    end
  end
end
