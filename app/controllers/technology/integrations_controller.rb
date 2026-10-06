module Technology
  class IntegrationsController < ApplicationController
    before_action :set_integration, only: %i[edit update destroy]

    def index
      authorize Integration
      scope = policy_scope(Integration).joins(app: :company).includes(app: :company)
      @counts = scope.group(:status).count
      scope = scope.where(status: params[:status]) if Integration.statuses.key?(params[:status])
      scope = scope.where(platform: params[:plataforma]) if params[:plataforma].present?
      scope = scope.where(environment: params[:ambiente]) if Integration.environments.key?(params[:ambiente])
      scope = scope.search(params[:q]) if params[:q].present?
      @integrations, @pager = paginate(scope.order("companies.trade_name", "apps.name", :platform))
      @platforms = Integration.distinct.order(:platform).pluck(:platform)
      all = Integration.includes(:app).to_a
      @kpis = { count: all.size, apps: all.map(&:app_id).uniq.size, active: all.select(&:active?), configuring: all.select(&:configuring?), disabled: all.select(&:disabled?) }
    end

    def new
      app = App.find_by(id: params[:aplicacao])
      @integration = authorize Integration.new(app: app, environment: app&.environment || "production", status: "configuring")
    end

    def create
      @integration = authorize Integration.new(integration_params)
      if @integration.save
        redirect_to return_path, notice: "Integração #{@integration.platform} cadastrada."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @integration.update(integration_params)
        redirect_to return_path, notice: "Integração atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @integration.destroy!
      redirect_to return_path, notice: "Integração excluída.", status: :see_other
    end

    private

    def set_integration
      @integration = authorize Integration.find(params[:id])
    end

    def integration_params
      params.expect(integration: %i[app_id platform variant environment status purpose notes])
    end

    def return_path
      params[:voltar] == "aplicacao" && @integration.app ? app_path(@integration.app) : integrations_path
    end
  end
end
