module Commercial
  # Quadro do pipeline (RF 7): leads até Qualificado, oportunidades de Reunião em diante.
  class PipelineController < ApplicationController
    LANES = [
      [ "new", "Novo Lead", :lead ], [ "contacted", "Contato Realizado", :lead ], [ "qualified", "Qualificado", :lead ],
      [ "meeting", "Reunião", :opportunity ], [ "proposal", "Proposta", :opportunity ], [ "negotiation", "Negociação", :opportunity ],
      [ "won", "Fechado", :opportunity ]
    ].freeze

    def show
      authorize :pipeline, :index?
      leads = policy_scope(Lead).open.includes(:service, :user)
      opportunities = policy_scope(Opportunity).where(stage: Opportunity::OPEN_STAGES)
                                               .or(policy_scope(Opportunity).stage_won.where(closed_on: Date.current.all_month))
                                               .includes(:company, :service, :user)
      if params[:responsavel].present?
        leads = leads.where(user_id: params[:responsavel])
        opportunities = opportunities.where(user_id: params[:responsavel])
      end
      if params[:servico].present?
        leads = leads.where(service_id: params[:servico])
        opportunities = opportunities.where(service_id: params[:servico])
      end
      leads = leads.where(origin: params[:origem]) if Lead.origins.key?(params[:origem])
      if params[:q].present?
        leads = leads.search(params[:q])
        opportunities = opportunities.search(params[:q])
      end

      lead_groups = leads.order(entered_on: :desc).group_by(&:status)
      opp_groups = opportunities.order(:expected_close_on).group_by(&:stage)
      @lanes = LANES.map do |key, label, kind|
        cards = kind == :lead ? lead_groups.fetch(key, []) : opp_groups.fetch(key, [])
        { key: key, label: label, kind: kind, cards: cards,
          total: kind == :opportunity ? cards.sum(&:estimated_value_cents) : nil,
          weighted: kind == :opportunity ? cards.sum(&:weighted_cents) : nil }
      end
      @users = User.active.by_name
      @services = Service.by_name
      open = Opportunity.open
      @kpis = {
        proposals_open: Proposal.where(status: %w[sent viewed]).count,
        proposals_value: Proposal.where(status: %w[sent viewed]).sum(:total_cents),
        weighted: open.sum(&:weighted_cents),
        won_month: Opportunity.stage_won.where(closed_on: Date.current.all_month).sum(:estimated_value_cents),
        open_deals: Lead.open.count + open.count
      }
    end
  end
end
