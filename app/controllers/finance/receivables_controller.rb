module Finance
  # Receitas (por competência) e Contas a receber (por vencimento): duas visões do mesmo
  # registro, Receivable (RF 23 e 25).
  class ReceivablesController < ApplicationController
    include FinancePeriod

    before_action :set_receivable, only: %i[edit update destroy new_payment pay cancel]

    STATUS_ORDER = %w[overdue pending forecast paid cancelled].freeze

    def index
      authorize Receivable
      @view = params[:visao] == "receitas" ? "receitas" : "receber"
      set_period(back: 12, forward: Setting[:recurrence_months].to_i)
      base = policy_scope(Receivable)
      base = @view == "receitas" ? base.where(competence: @range) : base.where(due_on: @range)
      @kpis = kpis(base)
      scope = base.joins(:company).includes(:company, :service, :contract, :customer_service, :invoice)
      # O filtro "Vencido" mostra todos os inadimplentes, de qualquer mês.
      scope = policy_scope(Receivable).joins(:company).includes(:company, :service, :contract, :customer_service, :invoice) if params[:status] == "overdue"
      @counts = base.group(:status).count.merge("overdue" => policy_scope(Receivable).overdue.count)
      scope = scope.where(status: params[:status]) if Receivable.statuses.key?(params[:status])
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.where(service_id: params[:servico]) if params[:servico].present?
      scope = scope.where(category: params[:categoria]) if params[:categoria].present?
      scope = scope.search(params[:q]) if params[:q].present?
      @totals = scope.not_cancelled.group(:status).sum(:amount_cents)
      scope = apply_sort(scope, {
        "situacao" => [ "Situação e vencimento", ->(s) { s.in_order_of(:status, STATUS_ORDER).order(:due_on, :id) } ],
        "vencimento" => [ "Vencimento", ->(s) { s.order(:due_on, :id) } ],
        "cliente" => [ "Cliente", ->(s) { s.order("companies.trade_name", :due_on) } ],
        "valor" => [ "Maior valor", ->(s) { s.order(amount_cents: :desc) } ]
      })
      @receivables, @pager = paginate(scope)
      @companies = Company.where(id: Receivable.select(:company_id)).by_name.select(:id, :trade_name)
      @services = Service.where(id: Receivable.select(:service_id)).by_name
    end

    def new
      company = Company.find_by(id: params[:empresa])
      @receivable = authorize Receivable.new(company: company, competence: Date.current.beginning_of_month, due_on: Date.current + 10)
    end

    def create
      @receivable = authorize Receivable.new(receivable_params)
      if @receivable.save
        redirect_to return_path, notice: "Receita “#{@receivable.description}” cadastrada como #{@receivable.status_label.downcase}."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @receivable.update(receivable_params)
        redirect_to return_path, notice: "Receita atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @receivable.recurring?
        redirect_to return_path, alert: "Título gerado pela recorrência não é excluído: cancele-o (a rotina não gera de novo a mesma competência)."
      else
        @receivable.destroy!
        redirect_to return_path, notice: "Receita excluída.", status: :see_other
      end
    end

    def new_payment; end

    def pay
      payment = params.expect(payment: %i[paid_on amount notes])
      if payment[:paid_on].present? && @receivable.register_payment!(paid_on: payment[:paid_on], amount: payment[:amount], notes: payment[:notes])
        redirect_to return_path, notice: "Pagamento de #{@receivable.company.trade_name} registrado em #{I18n.l(@receivable.paid_on)}."
      else
        @receivable.errors.add(:paid_on, "precisa ser informada") if payment[:paid_on].blank?
        render :new_payment, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordInvalid
      render :new_payment, status: :unprocessable_entity
    end

    def cancel
      @receivable.cancel!(params[:motivo].presence && "Cancelado: #{params[:motivo]}")
      redirect_to return_path, notice: "Receita cancelada; não entra mais no faturamento."
    end

    private

    def set_receivable
      @receivable = Receivable.find(params[:id])
      authorize @receivable, %w[new_payment pay cancel].include?(action_name) ? :update? : "#{action_name}?"
    end

    def receivable_params
      params.expect(receivable: %i[company_id contact_id service_id contract_id description category amount competence_month due_on paid_on notes])
    end

    def return_path
      params[:voltar] == "receitas" ? revenues_path : receivables_path
    end

    def kpis(base)
      Receivable.summary(base).merge(
        overdue_all: policy_scope(Receivable).overdue.sum(:amount_cents), overdue_all_count: policy_scope(Receivable).overdue.count,
        recurring: base.not_cancelled.where.not(customer_service_id: nil).sum(:amount_cents)
      )
    end
  end
end
