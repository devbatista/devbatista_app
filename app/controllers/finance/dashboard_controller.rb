module Finance
  # Dashboard financeiro (RF 22): 7 cartões do período, por competência.
  # Faturamento = Recebido + A receber + Vencido (os três status partem as receitas válidas).
  class DashboardController < ApplicationController
    include FinancePeriod

    def show
      authorize :finance, :show?
      set_period(back: 12, forward: 0)
      revenues = Receivable.where(competence: @range)
      expenses = Payable.where(competence: @range).not_cancelled
      @kpis = Receivable.summary(revenues).merge(expenses: expenses.sum(:amount_cents), mrr: CustomerService.active.sum(:mrr_cents))
      @kpis[:result] = @kpis[:billed] - @kpis[:expenses]
      # Variação do faturamento contra o mês anterior (só quando o período é um mês).
      if @range.count <= 31
        previous = Receivable.not_cancelled.where(competence: @range.first << 1).sum(:amount_cents)
        @kpis[:growth] = ((@kpis[:billed] - previous) * 100.0 / previous).round if previous.positive?
      end

      last = @range.last.beginning_of_month
      @months = (0..5).map { |i| last << (5 - i) }
      revenue_by_month = Receivable.not_cancelled.where(competence: @months.first..last).group(:competence).sum(:amount_cents)
      expense_by_month = Payable.not_cancelled.where(competence: @months.first..last).group(:competence).sum(:amount_cents)
      @series = @months.map { |m| { month: m, revenue: revenue_by_month[m].to_i, expense: expense_by_month[m].to_i } }
      @by_category = expenses.group(:category).sum(:amount_cents).sort_by { |_, v| -v }

      week = Date.current..(Date.current + 7)
      @receive_week = Receivable.where(status: %w[forecast pending], due_on: week).includes(:company, :service).order(:due_on).to_a
      @pay_week = Payable.where(status: %w[forecast pending], due_on: week).includes(:supplier, :company).order(:due_on).to_a
      @defaulters = Receivable.overdue.includes(:company, :service, :contract).order(:due_on).to_a
    end
  end
end
