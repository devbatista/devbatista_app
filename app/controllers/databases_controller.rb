class DatabasesController < ApplicationController
  before_action :set_database, only: %i[edit update destroy]

  def index
    authorize Database
    scope = policy_scope(Database).joins(app: :company).includes(app: :company)
    @counts = scope.group(:environment).count
    scope = scope.where(environment: params[:ambiente]) if Database.environments.key?(params[:ambiente])
    scope = scope.where(technology: params[:tecnologia]) if params[:tecnologia].present?
    scope = scope.where(apps: { company_id: params[:empresa] }) if params[:empresa].present?
    scope = scope.search(params[:q]) if params[:q].present?
    @databases, @pager = paginate(scope.order("companies.trade_name", "apps.name"))
    @technologies = Database.distinct.order(:technology).pluck(:technology)
    @companies = Company.where(id: App.where(id: Database.select(:app_id)).select(:company_id)).by_name.select(:id, :trade_name)
    all = Database.joins(:app).to_a
    @kpis = { count: all.size, apps: all.map(&:app_id).uniq.size, companies: App.where(id: all.map(&:app_id)).distinct.count(:company_id),
              production: all.count(&:env_production?), production_backup: all.count { |d| d.env_production? && d.backup? },
              by_tech: all.group_by(&:technology).transform_values(&:size).sort_by { |_, n| -n }, without_backup: all.reject(&:backup?) }
  end

  def new
    @database = authorize Database.new(app_id: params[:aplicacao], environment: App.find_by(id: params[:aplicacao])&.environment || "production")
  end

  def create
    @database = authorize Database.new(database_params)
    if @database.save
      redirect_to return_path, notice: "Banco de dados cadastrado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @database.update(database_params)
      redirect_to return_path, notice: "Banco de dados atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @database.destroy!
    redirect_to return_path, notice: "Banco de dados excluído.", status: :see_other
  end

  private

  def set_database
    @database = authorize Database.find(params[:id])
  end

  def database_params
    params.expect(database: %i[app_id technology version environment provider backup_policy vault_reference notes])
  end

  def return_path
    params[:voltar] == "aplicacao" && @database.app ? app_path(@database.app) : databases_path
  end
end
