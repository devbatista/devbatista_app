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
    load_operation
    load_finance
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

  # Projetos, chamados e horas da Visão 360º, só para quem pode ver cada área.
  def load_operation
    @projects = current_user.can_read?("projetos") ? @company.projects.includes(:user).order(Arel.sql("projects.status IN ('done','cancelled')"), start_date: :desc).to_a : []
    @project_hours = TimeEntry.where(project_id: @projects.map(&:id)).group(:project_id).sum(:minutes)
    @project_estimates = Task.where(project_id: @projects.map(&:id)).group(:project_id).sum(:estimated_minutes)
    @tickets = current_user.can_read?("suporte") ? @company.tickets.includes(:user, :contact).order(Arel.sql("tickets.status IN ('resolved','closed')"), opened_at: :desc).to_a : []
    @month_minutes = @company.time_entries.where(worked_on: Date.current.all_month).sum(:minutes) if current_user.can_read?("horas")
  end

  # Aba Financeiro: títulos a receber, notas fiscais e custo direto (só Financeiro e Administrador).
  def load_finance
    return @receivables = [] unless current_user.can_read?("financeiro")

    # Em aberto primeiro (vencidos e pendentes, depois previstos, por vencimento); depois os pagos mais recentes.
    @receivables = @company.receivables.includes(:contract, :service)
                           .order(Arel.sql("CASE WHEN receivables.status IN ('overdue','pending') THEN 0 WHEN receivables.status = 'forecast' THEN 1 ELSE 2 END"),
                                  Arel.sql("CASE WHEN receivables.status IN ('overdue','pending','forecast') THEN receivables.due_on END"), due_on: :desc)
                           .limit(40).to_a
    @invoices = @company.invoices.order(competence: :desc).limit(6).to_a
    @finance = {
      open: @company.receivables.where(status: %w[forecast pending]).where(due_on: ..Date.current.end_of_month).sum(:amount_cents),
      open_next: @company.receivables.where(status: %w[forecast pending]).minimum(:due_on),
      overdue: @company.receivables.overdue.sum(:amount_cents), overdue_count: @company.receivables.overdue.count,
      paid_year: @company.receivables.paid.where(paid_on: Date.current.all_year).sum(:amount_cents),
      first_paid: @company.receivables.paid.minimum(:paid_on),
      direct_cost_month: @company.direct_cost_cents(Date.current.all_month)
    }
  end

  def set_company
    @company = authorize Company.find(params[:id])
  end

  def company_params
    params.expect(company: %i[legal_name trade_name cnpj status phone email website street city state zip_code notes])
  end
end
