class SuppliersController < ApplicationController
  before_action :set_supplier, only: %i[edit update destroy]

  def index
    authorize Supplier
    month = Date.current.all_month
    scope = policy_scope(Supplier)
    @counts = scope.group(:category).count
    scope = scope.where(category: params[:categoria]) if params[:categoria].present?
    scope = scope.where(active: params[:situacao] != "inativos") unless params[:situacao] == "todos"
    scope = scope.search(params[:q]) if params[:q].present?
    spend_sql = "(SELECT COALESCE(SUM(amount_cents), 0) FROM payables p WHERE p.supplier_id = suppliers.id AND p.status <> 'cancelled' " \
                "AND p.competence = #{Supplier.connection.quote(month.first)})"
    scope = apply_sort(scope, {
      "gasto" => [ "Maior gasto no mês", ->(s) { s.order(Arel.sql("#{spend_sql} DESC"), :name) } ],
      "nome" => [ "Nome (A–Z)", ->(s) { s.order(:name) } ]
    })
    @suppliers, @pager = paginate(scope)
    payables = Payable.not_cancelled.where(competence: month.first)
    @spend = payables.where(supplier_id: @suppliers.map(&:id)).group(:supplier_id).sum(:amount_cents)
    @foreign = Payable.foreign.not_cancelled.where(supplier_id: @suppliers.map(&:id)).distinct.pluck(:supplier_id)
    @kpis = {
      active: Supplier.active.count, categories: Supplier.active.distinct.count(:category),
      month: payables.sum(:amount_cents), month_count: payables.count,
      foreign: Payable.foreign.not_cancelled.distinct.count(:supplier_id),
      services: ExternalService.active.count, service_suppliers: ExternalService.active.distinct.count(:supplier_id)
    }
    @services = ExternalService.active.where(supplier_id: @suppliers.map(&:id)).group(:supplier_id).count
    @rate = ExchangeRate.where(currency: "USD").order(quoted_on: :desc).first
  end

  def new
    @supplier = authorize Supplier.new(active: true)
  end

  def create
    @supplier = authorize Supplier.new(supplier_params)
    if @supplier.save
      redirect_to suppliers_path, notice: "Fornecedor #{@supplier.name} cadastrado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @documents = @supplier.documents.includes(:uploaded_by, file_attachment: :blob).recent if policy(Document).index?
  end

  def update
    if @supplier.update(supplier_params)
      redirect_to suppliers_path, notice: "Fornecedor #{@supplier.name} atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @supplier.destroy
      redirect_to suppliers_path, notice: "Fornecedor excluído.", status: :see_other
    else
      redirect_to suppliers_path, alert: "#{@supplier.name} tem despesas lançadas: desative em vez de excluir."
    end
  end

  private

  def set_supplier
    @supplier = authorize Supplier.find(params[:id])
  end

  def supplier_params
    params.expect(supplier: %i[name category contact_name phone email website notes active])
  end
end
