module Commercial
  class OpportunitiesController < ApplicationController
    include PipelineMoves

    before_action :set_opportunity, only: %i[edit update destroy]

    def index
      authorize Opportunity
      scope = policy_scope(Opportunity).joins(:company).includes(:company, :service, :user, :lead)
      @counts = scope.group(:stage).count
      scope = scope.where(stage: params[:etapa]) if Opportunity.stages.key?(params[:etapa])
      scope = scope.where(stage: Opportunity::OPEN_STAGES) if params[:etapa].blank?
      scope = scope.where(user_id: params[:responsavel]) if params[:responsavel].present?
      scope = scope.where(expected_close_on: Date.current.all_month) if params[:fechamento] == "mes"
      scope = scope.where(expected_close_on: ...Date.current) if params[:fechamento] == "atrasadas"
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "fechamento" => [ "Previsão de fechamento", ->(s) { s.order(Arel.sql("expected_close_on IS NULL"), :expected_close_on) } ],
        "valor" => [ "Maior valor", ->(s) { s.order(estimated_value_cents: :desc) } ],
        "ponderada" => [ "Maior ponderada", ->(s) { s.order(Arel.sql("estimated_value_cents * probability DESC")) } ]
      })
      @opportunities, @pager = paginate(scope)
      @users = User.active.by_name
      open = Opportunity.open
      @kpis = {
        open_value: open.sum(:estimated_value_cents),
        open_count: open.count,
        weighted: open.sum(&:weighted_cents),
        closing_month: open.where(expected_close_on: Date.current.all_month).count,
        closing_month_value: open.where(expected_close_on: Date.current.all_month).sum(:estimated_value_cents),
        won_month: Opportunity.stage_won.where(closed_on: Date.current.all_month).sum(:estimated_value_cents),
        won_month_count: Opportunity.stage_won.where(closed_on: Date.current.all_month).count
      }
    end

    def new
      @opportunity = authorize Opportunity.new(company_id: params[:empresa], user: current_user, stage: "meeting",
                                               probability: Opportunity::STAGE_PROBABILITY["meeting"], expected_close_on: Date.current + 30)
    end

    def create
      @opportunity = authorize Opportunity.new(opportunity_params)
      if @opportunity.save
        redirect_to return_path, notice: "Oportunidade cadastrada."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @opportunity.update(opportunity_params)
        redirect_to return_path, notice: "Oportunidade atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @opportunity.destroy!
      redirect_to opportunities_path, notice: "Oportunidade excluída.", status: :see_other
    end

    private

    def set_opportunity
      @opportunity = authorize Opportunity.find(params[:id])
    end

    def pipeline_record
      Opportunity.find(params[:id])
    end

    def opportunity_params
      permitted = params.expect(opportunity: %i[title company_id service_id user_id stage estimated_value probability expected_close_on notes next_step next_step_on])
      permitted.delete(:stage) unless permitted[:stage].in?(Opportunity::OPEN_STAGES + %w[won])
      permitted
    end

    def return_path
      params[:voltar] == "pipeline" ? pipeline_path : opportunities_path
    end
  end
end
