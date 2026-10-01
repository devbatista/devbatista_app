class CompaniesController < ApplicationController
  before_action :set_company, only: %i[show edit update]

  def index
    authorize Company
    scope = policy_scope(Company).includes(:primary_contact)
    @counts = scope.group(:status).count
    scope = scope.where(status: params[:status]) if Company.statuses.key?(params[:status])
    scope = scope.where(state: params[:uf]) if params[:uf].present?
    scope = scope.search(params[:q]) if params[:q].present?
    scope = apply_sort(scope, {
      "mrr" => [ "Maior MRR", ->(s) { s.order(Arel.sql("(SELECT COALESCE(SUM(mrr_cents), 0) FROM customer_services cs WHERE cs.company_id = companies.id AND cs.status = 'active') DESC, trade_name")) } ],
      "nome" => [ "Nome fantasia (A–Z)", ->(s) { s.order(:trade_name) } ],
      "desde" => [ "Cliente desde", ->(s) { s.order(Arel.sql("customer_since IS NULL, customer_since"), :trade_name) } ]
    })
    @companies, @pager = paginate(scope)
    @mrr = CustomerService.active.where(company_id: @companies.map(&:id)).group(:company_id).sum(:mrr_cents)
    @contracts = Contract.current.where(company_id: @companies.map(&:id)).group(:company_id).count
    @states = Company.where.not(state: nil).distinct.order(:state).pluck(:state)
    @kpis = {
      active: Company.active.count,
      new_quarter: Company.active.where(customer_since: Date.current.beginning_of_quarter..).count,
      prospects: Company.prospect.count,
      mrr: CustomerService.active.sum(:mrr_cents)
    }
  end

  # Visão 360º (RF 14).
  def show
    @tab = params[:aba].presence || "resumo"
    @contacts = @company.contacts.to_a
    @services = @company.customer_services.includes(:service, :contract).order(Arel.sql("customer_services.status = 'active' DESC"), :start_date)
    @contracts = @company.contracts.order(Arel.sql("contracts.status IN ('active','expiring') DESC"), end_date: :desc)
    @documents = policy(Document).index? ? @company.documents.includes(:uploaded_by, file_attachment: :blob).recent : Document.none
    @activities = @company.activities.includes(:user).recent.limit(50)
    @current_contract = @contracts.find { |c| c.active? || c.expiring? }
  end

  def new
    @company = authorize Company.new(status: "prospect")
  end

  def create
    @company = authorize Company.new(company_params)
    if @company.save
      redirect_to @company, notice: "Empresa cadastrada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @company.update(company_params)
      redirect_to @company, notice: "Dados da empresa atualizados."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_company
    @company = authorize Company.find(params[:id])
  end

  def company_params
    params.expect(company: %i[legal_name trade_name cnpj status phone email website street city state zip_code notes])
  end
end
