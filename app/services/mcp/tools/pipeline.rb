module Mcp
  module Tools
    # Mesmo quadro da tela do pipeline (Commercial::PipelineController): leads abertos por status,
    # oportunidades abertas por etapa e as fechadas no mês.
    class Pipeline < Base
      include CommercialData

      CARDS_PER_LANE = 20

      tool_name "pipeline"
      title "Pipeline comercial"
      description <<~TEXT.squish
        Visão do pipeline: leads abertos por status e oportunidades por etapa (as fechadas só do mês atual),
        com quantidade, valor total e valor ponderado por etapa, mais os indicadores do topo da tela.
        Cada etapa traz até #{CARDS_PER_LANE} registros; para ver todos, use buscar_leads ou buscar_oportunidades.
      TEXT
      read_only
      input_schema(
        properties: {
          termo: { type: "string", description: "Parte do nome do lead, da empresa ou do título da oportunidade" },
          responsavel_id: { type: "string", description: "Id do usuário responsável" },
          servico_id: { type: "string", description: "Id do serviço de interesse" },
          origem: { type: "string", enum: Lead::ORIGIN_LABELS.keys, description: "Filtra só os leads" }
        },
        additionalProperties: false
      )

      def execute(termo: nil, responsavel_id: nil, servico_id: nil, origem: nil)
        authorize(:pipeline, :index?)
        leads = policy_scope(Lead).open.includes(:service, :user)
        opportunities = policy_scope(Opportunity).open
                                                 .or(policy_scope(Opportunity).stage_won.where(closed_on: Date.current.all_month))
                                                 .includes(:company, :service, :user)
        filters = { user_id: responsavel_id.presence, service_id: servico_id.presence }.compact
        leads = leads.where(filters)
        opportunities = opportunities.where(filters)
        leads = leads.where(origin: origem) if origem
        if termo.present?
          leads = leads.search(termo)
          opportunities = opportunities.search(termo)
        end

        { etapas: lanes(leads.order(entered_on: :desc).group_by(&:status),
                        opportunities.order(:expected_close_on).group_by(&:stage)),
          indicadores: indicators }
      end

      private

      def lanes(lead_groups, opportunity_groups)
        Commercial::PipelineController::LANES.map do |key, label, kind|
          if kind == :lead
            cards = lead_groups.fetch(key, [])
            { etapa: key, rotulo: label, tipo: "lead", quantidade: cards.size,
              leads: cards.first(CARDS_PER_LANE).map { |lead| lead_data(lead) } }
          else
            cards = opportunity_groups.fetch(key, [])
            { etapa: key, rotulo: label, tipo: "oportunidade", quantidade: cards.size,
              valor_total: reais(cards.sum(&:estimated_value_cents)), valor_ponderado: reais(cards.sum(&:weighted_cents)),
              oportunidades: cards.first(CARDS_PER_LANE).map { |opportunity| opportunity_data(opportunity) } }
          end
        end
      end

      def indicators
        open = policy_scope(Opportunity).open
        waiting = policy_scope(Proposal).where(status: %w[sent viewed])
        {
          propostas_aguardando: waiting.count,
          valor_propostas_aguardando: reais(waiting.sum(:total_cents)),
          previsao_ponderada: reais(open.sum(&:weighted_cents)),
          fechado_no_mes: reais(policy_scope(Opportunity).stage_won.where(closed_on: Date.current.all_month).sum(:estimated_value_cents)),
          negocios_abertos: policy_scope(Lead).open.count + open.count
        }
      end
    end
  end
end
