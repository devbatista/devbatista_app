class ContractsController < ApplicationController
  before_action :set_contract, only: %i[show edit update]

  def index
    authorize Contract
    scope = policy_scope(Contract).joins(:company).includes(:company)
    @counts = scope.group(:status).count
    scope = scope.where(status: params[:status]) if Contract.statuses.key?(params[:status])
    scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
    scope = scope.where(renewal: params[:renovacao]) if Contract.renewals.key?(params[:renovacao])
    scope = scope.where(periodicity: params[:periodicidade]) if Contract.periodicities.key?(params[:periodicidade])
    scope = scope.search(params[:q]) if params[:q].present?
    scope = apply_sort(scope, {
      "vencimento" => [ "Término mais próximo", ->(s) { s.order(Arel.sql("contracts.status IN ('active','expiring') DESC"), :end_date) } ],
      "numero" => [ "Número", ->(s) { s.order(number: :desc) } ],
      "cliente" => [ "Cliente", ->(s) { s.order("companies.trade_name", :end_date) } ]
    })
    @contracts, @pager = paginate(scope)
    @expiring = Contract.includes(:company).where(status: %w[active expiring])
                        .where(end_date: Date.current..(Date.current + Setting[:contract_alert_days].max.days)).by_end_date
    @companies = Company.by_name.select(:id, :trade_name)
    current = Contract.current
    @kpis = {
      current: current.count,
      expiring: @expiring.size,
      manual_expiring: @expiring.count(&:renewal_manual?),
      monthly: current.sum(&:monthly_value_cents),
      mrr: CustomerService.active.sum(:mrr_cents),
      mrr_without_contract: CustomerService.active.where(contract_id: nil).sum(:mrr_cents)
    }
  end

  def show
    @services = @contract.customer_services.includes(:service)
    @documents = @contract.documents.includes(:uploaded_by, file_attachment: :blob).recent
    @history = AuditLog.where(auditable: @contract).includes(:user).recent.limit(20)
  end

  def new
    @contract = authorize Contract.new(company_id: params[:empresa], status: "active", renewal: "manual",
                                       periodicity: "monthly", start_date: Date.current, end_date: Date.current + 1.year - 1.day)
  end

  def create
    @contract = authorize Contract.new(contract_params)
    if @contract.save
      redirect_to @contract, notice: "Contrato #{@contract.code} cadastrado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @contract.update(contract_params)
      redirect_to @contract, notice: "Contrato #{@contract.code} atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_contract
    @contract = authorize Contract.find(params[:id])
  end

  def contract_params
    params.expect(contract: %i[company_id title status start_date end_date renewal value periodicity notes])
  end
end
