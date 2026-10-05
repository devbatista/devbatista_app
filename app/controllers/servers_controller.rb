class ServersController < ApplicationController
  before_action :set_server, only: %i[edit update destroy]

  def index
    authorize Server
    scope = policy_scope(Server).joins(:company).includes(:company, :supplier, :apps)
    @counts = scope.group(:environment).count
    scope = scope.where(environment: params[:ambiente]) if Server.environments.key?(params[:ambiente])
    scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
    scope = scope.where(supplier_id: params[:fornecedor]) if params[:fornecedor].present?
    scope = scope.search(params[:q]) if params[:q].present?
    @total = scope.sum(:monthly_cost_cents)
    scope = apply_sort(scope, {
      "nome" => [ "Nome (A–Z)", ->(s) { s.order(:name) } ],
      "custo" => [ "Maior custo", ->(s) { s.order(monthly_cost_cents: :desc) } ],
      "cliente" => [ "Cliente", ->(s) { s.order("companies.trade_name", :name) } ]
    })
    @servers, @pager = paginate(scope)
    @companies = Company.where(id: Server.select(:company_id)).by_name.select(:id, :trade_name)
    @suppliers = Supplier.where(id: Server.select(:supplier_id)).by_name
    all = Server.all
    @kpis = { count: all.count, by_env: all.group(:environment).count, total: all.sum(:monthly_cost_cents),
              production: all.env_production.sum(:monthly_cost_cents), top: all.includes(:company).order(monthly_cost_cents: :desc).first }
  end

  def new
    @server = authorize Server.new(company_id: params[:empresa], environment: "production", supplier: Supplier.find_by(name: "AWS"))
  end

  def create
    @server = authorize Server.new(server_params)
    if @server.save
      redirect_to servers_path, notice: "Servidor #{@server.name} cadastrado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @server.update(server_params)
      redirect_to servers_path, notice: "Servidor #{@server.name} atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @server.destroy!
    redirect_to servers_path, notice: "Servidor excluído.", status: :see_other
  end

  private

  def set_server
    @server = authorize Server.find(params[:id])
  end

  def server_params
    params.expect(server: %i[company_id supplier_id name host environment os instance_type monthly_cost vault_reference notes])
  end
end
