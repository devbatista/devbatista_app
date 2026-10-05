# Recorrências (RF 27): regras de receita (serviços contratados) e de despesa, a rotina diária
# e o botão "Executar rotina agora".
class RecurrencesController < ApplicationController
  def index
    authorize :recurrence, :index?
    @tab = params[:aba] == "despesas" ? "despesas" : "receitas"
    @horizon = RecurrenceRoutine.horizon
    window = Date.current..@horizon
    @services = CustomerService.recurring.includes(:company, :service, :contract).joins(:company)
    @services = @services.where(recurrence: params[:periodicidade]) if CustomerService.recurrences.key?(params[:periodicidade])
    @services = @services.where(status: params[:situacao]) if CustomerService.statuses.key?(params[:situacao])
    @services = @services.where("unaccent(companies.trade_name) ILIKE unaccent(:q)", q: "%#{CustomerService.sanitize_sql_like(params[:q].to_s.strip)}%") if params[:q].present? && @tab == "receitas"
    @services = @services.order(Arel.sql("customer_services.status = 'active' DESC"), "companies.trade_name").to_a
    @expenses = RecurringExpense.includes(:supplier, :company).by_supplier
    @expenses = @expenses.where(category: params[:categoria]) if params[:categoria].present?
    @expenses = @expenses.where("unaccent(suppliers.name) ILIKE unaccent(:q) OR unaccent(recurring_expenses.description) ILIKE unaccent(:q)", q: "%#{RecurringExpense.sanitize_sql_like(params[:q].to_s.strip)}%") if params[:q].present? && @tab == "despesas"
    @expenses = @expenses.order(Arel.sql("recurring_expenses.status = 'active' DESC")).to_a
    @next_receivables = Receivable.where(customer_service_id: @services.map(&:id), due_on: window).where.not(status: "cancelled").order(:due_on).group_by(&:customer_service_id)
    @cancelled_receivables = Receivable.cancelled.where(customer_service_id: @services.map(&:id)).group(:customer_service_id).count
    @next_payables = Payable.where(recurring_expense_id: @expenses.map(&:id), due_on: window).where.not(status: "cancelled").order(:due_on).group_by(&:recurring_expense_id)
    @cancelled_payables = Payable.cancelled.where(recurring_expense_id: @expenses.map(&:id)).group(:recurring_expense_id).count
    active_services = CustomerService.active.recurring
    active_expenses = RecurringExpense.active
    @kpis = {
      revenue_rules: active_services.count, mrr: active_services.sum(:mrr_cents),
      forecast: Receivable.where(customer_service_id: active_services.select(:id), due_on: (Date.current.next_month.beginning_of_month)..@horizon).not_cancelled.sum(:amount_cents),
      expense_rules: active_expenses.count,
      expense_month: active_expenses.sum { |e| (e.foreign? ? (e.amount_cents * (ExchangeRate.rate_for(e.currency) || 0)).round : e.amount_cents) / RecurringExpense::PERIOD_MONTHS[e.periodicity] }
    }
    @runs = RecurrenceRun.recent.includes(:user).limit(6).to_a
  end

  def run
    authorize :recurrence, :create?
    run = RecurrenceRoutine.new(Date.current, user: current_user).run!
    notice = "Rotina executada: #{run.generated_count} títulos gerados, #{run.overdue_count} marcados como vencidos, #{run.cancelled_count} cancelados."
    redirect_to recurrences_path(aba: params[:aba]), notice: notice
  end
end
