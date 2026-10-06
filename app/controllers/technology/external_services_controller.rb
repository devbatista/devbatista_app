module Technology
  class ExternalServicesController < ApplicationController
    before_action :set_service, only: %i[edit update destroy]

    def index
      authorize ExternalService
      scope = policy_scope(ExternalService).joins(:company).includes(:company, :supplier, :app)
      @counts = scope.group(:paid_by).count
      scope = scope.where(paid_by: params[:pagador]) if ExternalService::PAID_BY_LABELS.key?(params[:pagador])
      scope = scope.where(periodicity: params[:periodicidade]) if ExternalService.periodicities.key?(params[:periodicidade])
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.search(params[:q]) if params[:q].present?
      @services, @pager = paginate(scope.order(Arel.sql("external_services.paid_by = 'devbatista' DESC"), "companies.trade_name", :name))
      @companies = Company.where(id: ExternalService.select(:company_id)).by_name.select(:id, :trade_name)
      @rate = ExchangeRate.lookup("USD")
      active = ExternalService.active.includes(:company).to_a
      ours = active.select(&:paid_by_devbatista?)
      theirs = active.select(&:paid_by_client?)
      @by_company = ours.group_by(&:company).transform_values { |list| list.sum(&:monthly_brl_cents) }.sort_by { |_, v| -v }
      @kpis = { ours: ours.sum(&:monthly_brl_cents), ours_count: ours.size, ours_companies: ours.map(&:company_id).uniq.size,
                theirs: theirs.sum(&:monthly_brl_cents), theirs_count: theirs.size, count: active.size,
                by_periodicity: active.group_by(&:periodicity_label).transform_values(&:size) }
      @example = @by_company.first&.first
    end

    def new
      @service = authorize ExternalService.new(company_id: params[:empresa], app_id: params[:aplicacao], currency: "USD", periodicity: "monthly", paid_by: "devbatista")
      @service.company_id ||= @service.app&.company_id
    end

    def create
      @service = authorize ExternalService.new(service_params)
      if @service.save
        redirect_to return_path, notice: "Serviço externo #{@service.name} cadastrado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @service.update(service_params)
        redirect_to return_path, notice: "Serviço externo atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @service.destroy!
      redirect_to external_services_path, notice: "Serviço externo excluído.", status: :see_other
    end

    private

    def set_service
      @service = authorize ExternalService.find(params[:id])
    end

    def service_params
      params.expect(external_service: %i[name plan supplier_id company_id app_id currency cost periodicity paid_by active vault_reference notes])
    end

    def return_path
      params[:voltar] == "aplicacao" && @service.app ? app_path(@service.app) : external_services_path
    end
  end
end
