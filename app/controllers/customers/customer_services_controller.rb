module Customers
  class CustomerServicesController < ApplicationController
    before_action :set_customer_service, only: %i[edit update]

    def index
      authorize CustomerService
      scope = policy_scope(CustomerService).joins(:company, :service).includes(:company, :service, :contract)
      @counts = scope.group(:status).count
      scope = scope.where(status: params[:status]) if CustomerService.statuses.key?(params[:status])
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.where(service_id: params[:servico]) if params[:servico].present?
      scope = scope.where(recurrence: params[:recorrencia]) if CustomerService.recurrences.key?(params[:recorrencia])
      if params[:q].present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].strip)}%"
        scope = scope.where("unaccent(companies.trade_name) ILIKE unaccent(:q) OR unaccent(services.name) ILIKE unaccent(:q)", q: like)
      end
      scope = apply_sort(scope, {
        "cliente" => [ "Cliente", ->(s) { s.order("companies.trade_name", mrr_cents: :desc) } ],
        "mrr" => [ "Maior MRR", ->(s) { s.order(mrr_cents: :desc) } ],
        "inicio" => [ "Início mais recente", ->(s) { s.order(start_date: :desc) } ]
      })
      @customer_services, @pager = paginate(scope)
      @companies = Company.by_name.select(:id, :trade_name)
      @services = Service.by_name.select(:id, :name)
      active = CustomerService.active
      @kpis = {
        mrr: active.sum(:mrr_cents),
        clients: active.recurring.distinct.count(:company_id),
        recurring: active.recurring.count,
        monthly: active.monthly.count,
        one_off_cents: active.one_off.sum(:price_cents),
        one_off: active.one_off.count,
        suspended: CustomerService.suspended.count,
        suspended_cents: CustomerService.suspended.sum { |cs| CustomerService.mrr_for(cs.price_cents, cs.recurrence) }
      }
      @by_recurrence = active.group(:recurrence).pluck(:recurrence, Arel.sql("COUNT(*)"), Arel.sql("SUM(price_cents)"), Arel.sql("SUM(mrr_cents)"))
                             .to_h { |rec, count, price, mrr| [ rec, { count: count, price: price, mrr: mrr } ] }
    end

    def new
      @customer_service = authorize CustomerService.new(company_id: params[:empresa], recurrence: "monthly", status: "active", start_date: Date.current, due_day: 10)
    end

    def create
      @customer_service = authorize CustomerService.new(customer_service_params)
      @customer_service.price ||= @customer_service.service&.default_price
      if @customer_service.save
        redirect_to return_path, notice: "Serviço contratado cadastrado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @customer_service.update(customer_service_params)
        redirect_to return_path, notice: "Serviço contratado atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_customer_service
      @customer_service = authorize CustomerService.find(params[:id])
    end

    def customer_service_params
      params.expect(customer_service: %i[company_id service_id contract_id price recurrence start_date due_day status description notes])
    end

    def return_path
      params[:voltar] == "empresa" ? company_path(@customer_service.company, aba: "servicos") : customer_services_path
    end
  end
end
