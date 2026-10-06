module Products
  # Assinaturas dos produtos próprios, registradas à mão no MVP (RF 35).
  class SubscriptionsController < ApplicationController
    before_action :set_subscription, only: %i[edit update destroy]

    def index
      authorize Subscription
      scope = policy_scope(Subscription).includes(:product, :company)
      scope = scope.where(product_id: params[:produto]) if params[:produto].present?
      @counts = scope.group(:status).count
      scope = scope.where(status: params[:status]) if Subscription.statuses.key?(params[:status])
      scope = scope.where(plan: params[:plano]) if params[:plano].present?
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "situacao" => [ "Situação", ->(s) { s.in_order_of(:status, %w[delinquent active trial cancelled]).order(started_on: :desc) } ],
        "inicio" => [ "Início mais recente", ->(s) { s.order(started_on: :desc) } ],
        "assinante" => [ "Assinante (A–Z)", ->(s) { s.order(:subscriber_name) } ]
      })
      @subscriptions, @pager = paginate(scope)
      @products = Product.by_name
      @plans = Subscription.distinct.order(:plan).pluck(:plan)
      all = Subscription.includes(:product).to_a
      active = all.select { |s| s.counts_on?(Date.current) }
      cancelled_month = all.count { |s| s.cancelled? && s.cancelled_on&.between?(Date.current.beginning_of_month, Date.current) }
      active_start = all.count { |s| s.counts_on?(Date.current.prev_month.end_of_month) }
      @kpis = { active: active.size, by_product: active.group_by { |s| s.product.name }.transform_values(&:size),
                mrr: active.sum(&:monthly_value_cents), trial: all.select(&:trial?), delinquent: all.select(&:delinquent?),
                cancelled_month: cancelled_month, churn: (active_start.positive? ? (cancelled_month * 100.0 / active_start).round(1) : nil) }
    end

    def new
      @subscription = authorize Subscription.new(product_id: params[:produto], status: "active", started_on: Date.current, plan: "Profissional")
    end

    def create
      @subscription = authorize Subscription.new(subscription_params)
      if @subscription.save
        redirect_to subscriptions_path, notice: "Assinatura de #{@subscription.subscriber_name} registrada."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @subscription.update(subscription_params)
        redirect_to subscriptions_path, notice: "Assinatura de #{@subscription.subscriber_name} atualizada (#{@subscription.status_label.downcase})."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @subscription.destroy!
      redirect_to subscriptions_path, notice: "Assinatura excluída.", status: :see_other
    end

    private

    def set_subscription
      @subscription = authorize Subscription.find(params[:id])
    end

    def subscription_params
      params.expect(subscription: %i[product_id company_id subscriber_name email plan monthly_value started_on trial_ends_on cancelled_on status notes])
    end
  end
end
