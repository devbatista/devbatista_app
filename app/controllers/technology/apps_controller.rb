module Technology
  class AppsController < ApplicationController
    before_action :set_app, only: %i[show edit update destroy]

    def index
      authorize App
      scope = policy_scope(App).joins(:company).preload(:company, :hosting)
      @counts = scope.group(:status).count
      scope = scope.where(status: params[:status]) if App.statuses.key?(params[:status])
      scope = scope.where(environment: params[:ambiente]) if App.environments.key?(params[:ambiente])
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.where(hosting_type: params[:hospedagem]) if App::HOSTING_TYPES.include?(params[:hospedagem])
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "cliente" => [ "Cliente", ->(s) { s.order("companies.trade_name", :name) } ],
        "nome" => [ "Nome (A–Z)", ->(s) { s.order(:name) } ],
        "recentes" => [ "Cadastro mais recente", ->(s) { s.order(created_at: :desc) } ]
      })
      @apps, @pager = paginate(scope)
      @companies = Company.where(id: App.select(:company_id)).by_name.select(:id, :trade_name)
      @open_tickets = Ticket.open.where(app_id: @apps.map(&:id)).group(:app_id).count
      servers = Server.sum(:monthly_cost_cents)
      services = ExternalService.active.paid_by_devbatista.to_a.sum(&:monthly_brl_cents)
      @kpis = {
        total: App.count, companies: App.distinct.count(:company_id),
        production: App.active.env_production.count,
        maintenance: App.maintenance.includes(:company).to_a,
        servers: servers, services: services
      }
    end

    def show
      @databases = @app.databases.to_a
      @integrations = @app.integrations.order(:platform).to_a
      @services = (@app.external_services.includes(:supplier).to_a | [ (@app.hosting if @app.hosting.is_a?(ExternalService)) ].compact)
      @domain = @app.domain
      @tickets = @app.tickets.includes(:user).order(opened_at: :desc).limit(5).to_a if current_user.can_read?("suporte")
      @history = AuditLog.where(auditable: @app).includes(:user).recent.limit(8)
    end

    def new
      @app = authorize App.new(company_id: params[:empresa], environment: "production", status: "active")
    end

    def create
      @app = authorize App.new(app_params)
      if @app.save
        redirect_to @app, notice: "Aplicação #{@app.name} cadastrada."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @app.update(app_params)
        redirect_to @app, notice: "Aplicação atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @app.destroy!
      redirect_to apps_path, notice: "Aplicação excluída.", status: :see_other
    end

    private

    def set_app
      @app = authorize App.find(params[:id])
    end

    def app_params
      params.expect(app: %i[company_id name description environment status url tech_stack repository_url hosting_key project_id contract_id user_id vault_reference])
    end
  end
end
