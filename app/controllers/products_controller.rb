# Produtos próprios (RF 35): cartões por produto e indicadores dos últimos meses.
class ProductsController < ApplicationController
  before_action :set_product, only: %i[edit update destroy]

  def index
    authorize Product
    scope = policy_scope(Product).includes(:subscriptions, :costs)
    @counts = scope.group(:status).count
    scope = scope.where(status: params[:status]) if Product.statuses.key?(params[:status])
    @products = scope.in_order_of(:status, %w[operating development idea discontinued]).order(:name).to_a
    all = Product.includes(:subscriptions, :costs).to_a
    @kpis = summary(all, Date.current)
    @previous = summary(all, Date.current.prev_month.end_of_month)
    @new_this_month = Subscription.where(started_on: Date.current.all_month).group(:product_id).count
  end

  # Indicadores dos produtos: séries de MRR, clientes e custo dos últimos 6 ou 12 meses.
  def indicators
    authorize Product, :index?
    @span = params[:periodo] == "12" ? 12 : 6
    @products = Product.includes(:subscriptions, :costs).in_order_of(:status, %w[operating development idea discontinued]).order(:name).to_a
    @products = @products.select { |p| p.id.to_s == params[:produto] } if params[:produto].present?
    current = Date.current.beginning_of_month
    @months = (0...@span).map { |i| current << (@span - 1 - i) }
    @series = @products.index_with do |p|
      @months.map { |m| on = m == current ? Date.current : m.end_of_month; { mrr: p.mrr_cents(on), clients: p.clients_count(on), cost: p.monthly_cost_cents(on) } }
    end
    @totals = @months.each_index.map { |i| %i[mrr clients cost].index_with { |k| @series.values.sum { |s| s[i][k] } } }
  end

  def new
    @product = authorize Product.new(status: "idea")
  end

  def create
    @product = authorize Product.new(product_params)
    if @product.save
      redirect_to products_path, notice: "Produto #{@product.name} cadastrado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @product.update(product_params)
      redirect_to products_path, notice: "Produto #{@product.name} atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @product.destroy
      redirect_to products_path, notice: "Produto excluído.", status: :see_other
    else
      redirect_to products_path, alert: "#{@product.name} tem assinaturas: mude o status para Descontinuado."
    end
  end

  private

  def set_product
    @product = authorize Product.find(params[:id])
  end

  def product_params
    params.expect(product: %i[name url description status monthly_cost notes])
  end

  def summary(products, on)
    mrr = products.sum { |p| p.mrr_cents(on) }
    cost = products.sum { |p| p.monthly_cost_cents(on) }
    { mrr: mrr, clients: products.sum { |p| p.clients_count(on) }, cost: cost, result: mrr - cost,
      margin: (((mrr - cost) * 100.0 / mrr).round(1) if mrr.positive?),
      by_product: products.select { |p| p.clients_count(on).positive? }.map { |p| [ p.name, p.clients_count(on) ] } }
  end
end
