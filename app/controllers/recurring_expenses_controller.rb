# Edição e encerramento das despesas recorrentes (a regra nasce em "Nova despesa → Recorrente").
class RecurringExpensesController < ApplicationController
  before_action :set_rule

  def edit; end

  def update
    if @rule.update(params.expect(recurring_expense: %i[supplier_id external_service_id description category cost_center_key currency amount periodicity due_day notes]))
      redirect_to recurrences_path(aba: "despesas"), notice: "Despesa recorrente atualizada; os títulos futuros não pagos seguem o novo valor."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def finish
    ended_on = params[:ended_on].present? ? Date.parse(params[:ended_on]) : Date.current
    @rule.update!(status: "ended", ended_on: ended_on)
    redirect_to recurrences_path(aba: "despesas"), notice: "Despesa recorrente encerrada em #{I18n.l(ended_on)}; os títulos posteriores foram cancelados."
  end

  private

  def set_rule
    @rule = authorize RecurringExpense.find(params[:id]), :update?
  end
end
