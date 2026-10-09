module Commercial
  class LeadsController < ApplicationController
    include PipelineMoves

    before_action :set_lead, only: %i[show edit update destroy]

    def index
      authorize Lead
      scope = policy_scope(Lead).includes(:service, :user, :company)
      @counts = scope.group(:status).count
      scope = scope.where(status: params[:status]) if Lead.statuses.key?(params[:status])
      scope = scope.where(origin: params[:origem]) if Lead.origins.key?(params[:origem])
      scope = scope.where(user_id: params[:responsavel]) if params[:responsavel].present?
      scope = scope.where(entered_on: period_range) if params[:periodo].present?
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "entrada" => [ "Entrada mais recente", ->(s) { s.order(entered_on: :desc, created_at: :desc) } ],
        "nome" => [ "Nome (A–Z)", ->(s) { s.order(:name) } ]
      })
      @leads, @pager = paginate(scope)
      @users = User.active.by_name
      month = Date.current.all_month
      @kpis = {
        new_month: Lead.where(entered_on: month).count,
        open: Lead.open.count,
        converted: Lead.where(converted_at: 90.days.ago..).count,
        entered_90: Lead.where(entered_on: 90.days.ago.to_date..).count,
        lost_month: Lead.where(lost_at: month).count
      }
      @by_origin = Lead.where(entered_on: 90.days.ago.to_date..).group(:origin).count.sort_by { |_, n| -n }
    end

    def show
      @interactions = @lead.interactions.includes(:user).recent
      @history = AuditLog.where(auditable: @lead).includes(:user).recent.limit(20)
    end

    def new
      @lead = authorize Lead.new(user: current_user, entered_on: Date.current, status: "new")
    end

    def create
      @lead = authorize Lead.new(lead_params)
      if @lead.save
        redirect_to (params[:voltar] == "pipeline" ? pipeline_path : @lead), notice: "Lead cadastrado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @lead.update(lead_params)
        redirect_to @lead, notice: "Lead atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @lead.destroy!
      redirect_to leads_path, notice: "Lead excluído.", status: :see_other
    end

    private

    def set_lead
      @lead = authorize Lead.find(params[:id])
    end

    def pipeline_record
      Lead.find(params[:id])
    end

    def lead_params
      permitted = %i[name company_name phone whatsapp email origin service_id user_id entered_on notes next_step next_step_on]
      permitted << :status if @lead.nil? || @lead.open?
      params.expect(lead: permitted).tap { |p| p.delete(:status) unless p[:status].in?(Lead::OPEN_STATUSES) }
    end

    def period_range
      case params[:periodo]
      when "mes" then Date.current.all_month
      when "30d" then 30.days.ago.to_date..Date.current
      when "90d" then 90.days.ago.to_date..Date.current
      else ..Date.current
      end
    end
  end
end
