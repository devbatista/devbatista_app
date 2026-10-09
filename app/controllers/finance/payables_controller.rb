module Finance
  # Despesas (por competência) e Contas a pagar (por vencimento): duas visões do mesmo
  # registro, Payable (RF 24 e 26). Despesa recorrente cria a regra que gera os próximos títulos.
  class PayablesController < ApplicationController
    include FinancePeriod

    before_action :set_payable, only: %i[edit update destroy new_payment pay cancel]

    STATUS_ORDER = %w[overdue pending forecast paid cancelled].freeze

    def index
      authorize Payable
      @view = params[:visao] == "despesas" ? "despesas" : "pagar"
      set_period(back: 12, forward: Setting[:recurrence_months].to_i)
      base = policy_scope(Payable)
      base = @view == "despesas" ? base.where(competence: @range) : base.where(due_on: @range)
      @kpis = kpis(base)
      @by_category = base.not_cancelled.group(:category).sum(:amount_cents).sort_by { |_, v| -v }
      all = policy_scope(Payable).joins(:supplier).includes(:supplier, :company, :recurring_expense, :external_service)
      scope = params[:status] == "overdue" ? all : base.joins(:supplier).includes(:supplier, :company, :recurring_expense, :external_service)
      @counts = (@view == "despesas" ? base.group(:category) : base.group(:status)).count
      @counts["overdue"] = policy_scope(Payable).overdue.count if @view == "pagar"
      scope = scope.where(status: params[:status]) if Payable.statuses.key?(params[:status])
      scope = scope.where(category: params[:categoria]) if params[:categoria].present?
      scope = scope.where(supplier_id: params[:fornecedor]) if params[:fornecedor].present?
      scope = filter_cost_center(scope)
      scope = scope.where.not(recurring_expense_id: nil) if params[:recorrencia] == "recorrentes"
      scope = scope.where(recurring_expense_id: nil) if params[:recorrencia] == "avulsas"
      scope = scope.search(params[:q]) if params[:q].present?
      @total = scope.not_cancelled.sum(:amount_cents)
      scope = apply_sort(scope, {
        "situacao" => [ "Situação e vencimento", ->(s) { s.in_order_of(:status, STATUS_ORDER).order(:due_on, :created_at) } ],
        "vencimento" => [ "Vencimento", ->(s) { s.order(:due_on, :created_at) } ],
        "fornecedor" => [ "Fornecedor", ->(s) { s.order("suppliers.name", :due_on) } ],
        "valor" => [ "Maior valor", ->(s) { s.order(amount_cents: :desc) } ]
      })
      @payables, @pager = paginate(scope)
      @suppliers = Supplier.where(id: Payable.select(:supplier_id)).by_name
    end

    def new
      supplier = Supplier.find_by(id: params[:fornecedor])
      @payable = authorize Payable.new(supplier: supplier, category: supplier&.category, currency: "BRL",
                                       competence: Date.current.beginning_of_month, due_on: Date.current + 10)
      @recurring = "0"
    end

    def create
      @payable = authorize Payable.new(payable_params)
      @recurring = params[:recorrente].to_s
      saved = Payable.transaction do
        if @recurring == "1"
          rule = @payable.recurring_expense = build_rule
          rule.errors.full_messages.each { |m| @payable.errors.add(:base, "Recorrência: #{m}") } unless rule.valid?
        end
        (@payable.errors.none? && @payable.save) || raise(ActiveRecord::Rollback)
      end
      if saved
        redirect_to return_path, notice: "Despesa “#{@payable.description}” cadastrada#{' com recorrência ' + @payable.recurring_expense.periodicity_label.downcase if @payable.recurring?}."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @payable.update(payable_params)
        redirect_to return_path, notice: "Despesa atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @payable.recurring?
        redirect_to return_path, alert: "Título gerado pela recorrência não é excluído: cancele-o ou encerre a despesa recorrente."
      else
        @payable.destroy!
        redirect_to return_path, notice: "Despesa excluída.", status: :see_other
      end
    end

    def new_payment
      @rate = ExchangeRate.lookup(@payable.currency, Date.current) if @payable.foreign?
    end

    def pay
      payment = params.expect(payment: %i[paid_on original_amount rate amount notes])
      if payment[:paid_on].present? && @payable.register_payment!(**payment.to_h.symbolize_keys.merge(paid_on: Date.parse(payment[:paid_on])))
        redirect_to return_path, notice: "Pagamento a #{@payable.supplier.name} registrado: #{helpers.brl(@payable.amount_cents)}."
      else
        @payable.errors.add(:paid_on, "precisa ser informada") if payment[:paid_on].blank?
        @rate = ExchangeRate.lookup(@payable.currency, Date.current) if @payable.foreign?
        render :new_payment, status: :unprocessable_entity
      end
    end

    def cancel
      @payable.cancel!(params[:motivo].presence && "Cancelado: #{params[:motivo]}")
      redirect_to return_path, notice: "Despesa cancelada."
    end

    private

    def set_payable
      @payable = Payable.find(params[:id])
      authorize @payable, %w[new_payment pay cancel].include?(action_name) ? :update? : "#{action_name}?"
    end

    def payable_params
      params.expect(payable: %i[supplier_id external_service_id description category currency original_amount amount competence_month due_on paid_on cost_center_key notes])
    end

    # Regra criada a partir da primeira despesa: mesmo valor, dia de vencimento e centro de custo.
    def build_rule
      p = @payable
      RecurringExpense.new(supplier: p.supplier, description: p.description.sub(/\s+—\s+\p{L}+\/\d{4}\z/, ""), category: p.category.presence || p.supplier&.category,
                           company_id: p.company_id, cost_center: p.cost_center, currency: p.currency,
                           amount_cents: p.foreign? ? p.original_amount_cents : p.amount_cents, periodicity: params[:periodicidade].presence_in(RecurringExpense.periodicities.keys) || "monthly",
                           due_day: p.due_on&.day, start_on: p.due_on, external_service_id: p.external_service_id)
    end

    def filter_cost_center(scope)
      case params[:centro].to_s
      when "interno" then scope.where(company_id: nil)
      when /\Acompany:(\d+)\z/ then scope.where(company_id: Regexp.last_match(1))
      when /\Aarea:(.+)\z/ then scope.where(company_id: nil, cost_center: Regexp.last_match(1))
      else scope
      end
    end

    def return_path
      params[:voltar] == "despesas" ? expenses_path : payables_path
    end

    def kpis(base)
      valid = base.not_cancelled
      {
        total: valid.sum(:amount_cents), count: valid.count,
        paid: base.paid.sum(:amount_cents),
        open: base.where(status: %w[forecast pending]).sum(:amount_cents),
        week: policy_scope(Payable).where(status: %w[forecast pending]).where(due_on: Date.current..(Date.current + 7)).sum(:amount_cents),
        overdue: base.overdue.sum(:amount_cents), overdue_count: base.overdue.count,
        overdue_all: policy_scope(Payable).overdue.sum(:amount_cents), overdue_all_count: policy_scope(Payable).overdue.count,
        direct: valid.where.not(company_id: nil).sum(:amount_cents), direct_clients: valid.where.not(company_id: nil).distinct.count(:company_id),
        foreign: valid.foreign.sum(:amount_cents), foreign_original: valid.foreign.group(:currency).sum(:original_amount_cents)
      }
    end
  end
end
