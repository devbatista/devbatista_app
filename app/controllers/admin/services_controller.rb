module Admin
  # Catálogo de serviços (RF 15).
  class ServicesController < ApplicationController
    before_action :set_service, only: %i[edit update]

    def index
      authorize Service
      scope = policy_scope(Service)
      @counts = scope.group(:status).count
      scope = scope.where(status: params[:status]) if Service.statuses.key?(params[:status])
      scope = scope.where(category: params[:categoria]) if params[:categoria].present?
      scope = scope.where("unaccent(name) ILIKE unaccent(?)", "%#{Service.sanitize_sql_like(params[:q].strip)}%") if params[:q].present?
      @services, @pager = paginate(scope.order(:category, :name))
      @in_use = CustomerService.active.group(:service_id).count
    end

    def new
      @service = authorize Service.new(kind: "recurring", status: "active", category: Service::CATEGORIES.first)
    end

    def create
      @service = authorize Service.new(service_params)
      if @service.save
        redirect_to admin_services_path, notice: "Serviço incluído no catálogo."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @service.update(service_params)
        redirect_to admin_services_path, notice: "Serviço atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_service
      @service = authorize Service.find(params[:id])
    end

    def service_params
      params.expect(service: %i[name description category kind default_price status])
    end
  end
end
