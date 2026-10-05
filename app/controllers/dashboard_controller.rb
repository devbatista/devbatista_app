# Dashboard executivo (RF 3): 12 cartões do período, 6 gráficos dos últimos 6 meses e o feed de
# atividades. Cartões e gráficos financeiros só para quem vê o financeiro (Administrador e
# Financeiro). Os números ficam em cache por até 15 minutos.
class DashboardController < ApplicationController
  include FinancePeriod

  CACHE_TTL = 15.minutes

  def show
    authorize :dashboard, :show?
    set_period(back: 12, forward: 0)
    @financial = current_user.sees_financials?
    @data = Rails.cache.fetch([ "dashboard", @period, @financial, Date.current ], expires_in: CACHE_TTL) { build_data }
    areas = Role::AREAS.keys.select { |a| current_user.can_read?(a) }
    @activities = Activity.where(area: areas).includes(:user, :subject).recent.limit(8)
  end

  private

  def build_data
    metrics = Metrics.new(@range)
    previous = Metrics.new(Metrics.previous_range(@range))
    data = {
      generated_at: Time.current,
      clients: Metrics.active_clients.count, new_clients_quarter: Company.where(customer_since: Date.current.beginning_of_quarter..).count,
      contracts: Contract.current.count, contracts_expiring: Contract.current.where(end_date: Date.current..(Date.current + 60)).count,
      projects: Project.active.count, projects_late: Project.late.count,
      tickets: Ticket.open.count, tickets_critical: Ticket.open.critical.count,
      proposals: metrics.open_proposals
    }
    return data unless @financial

    billing = metrics.billing
    companies = Company.where(id: metrics.revenue_by_company.keys).pluck(:id, :trade_name).to_h
    data.merge(
      billing: billing, previous_billed: previous.billing[:billed], expenses: metrics.expenses_cents, mrr: Metrics.mrr_at([ @range.last, Date.current ].min),
      overdue: Receivable.overdue.sum(:amount_cents), overdue_count: Receivable.overdue.count,
      series: metrics.monthly_series(6),
      by_service: metrics.revenue_by_service.sort_by { |_, v| -v },
      by_company: metrics.revenue_by_company.map { |id, v| [ companies[id], v ] }.sort_by { |_, v| -v }
    )
  end
end
