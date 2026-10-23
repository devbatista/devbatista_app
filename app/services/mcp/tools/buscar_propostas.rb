module Mcp
  module Tools
    class BuscarPropostas < Base
      include CommercialData

      tool_name "buscar_propostas"
      title "Buscar propostas"
      description <<~TEXT.squish
        Lista propostas comerciais, das mais recentes para as mais antigas. Filtra por termo (título ou código,
        como P-2026-012), status, empresa, lead e oportunidade. Use ver_proposta para os itens e as condições.
      TEXT
      read_only
      input_schema(
        properties: {
          termo: { type: "string", description: "Parte do título ou o código da proposta" },
          status: { type: "array", items: { type: "string", enum: Proposal::STATUS_LABELS.keys }, description: "Um ou mais status" },
          empresa_id: { type: "string" },
          lead_id: { type: "string" },
          oportunidade_id: { type: "string" },
          so_abertas: { type: "boolean", description: "Só Rascunho, Enviada e Visualizada" },
          **PAGINATION
        },
        additionalProperties: false
      )

      def execute(termo: nil, status: nil, empresa_id: nil, lead_id: nil, oportunidade_id: nil, so_abertas: false, pagina: nil, por_pagina: nil)
        authorize(Proposal, :index?)
        scope = policy_scope(Proposal).includes(:company, :lead, :user).order(created_at: :desc)
        scope = scope.search(termo) if termo.present?
        scope = scope.where(status: status) if status.present?
        scope = scope.where({ company_id: empresa_id.presence, lead_id: lead_id.presence, opportunity_id: oportunidade_id.presence }.compact)
        scope = scope.open if so_abertas
        proposals, pager = paginate(scope, pagina, por_pagina)

        { propostas: proposals.map { |proposal| proposal_data(proposal) }, paginacao: pager }
      end
    end
  end
end
