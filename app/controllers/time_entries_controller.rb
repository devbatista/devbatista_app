class TimeEntriesController < ApplicationController
  before_action :set_entry, only: %i[edit update destroy]

  HOURS_PER_DAY = 8

  def index
    authorize TimeEntry
    set_period
    base = policy_scope(TimeEntry).where(worked_on: @range)
    scope = base.includes(:user, :company, :project, :task, :ticket)
    scope = scope.where(user_id: params[:usuario]) if params[:usuario].present?
    scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
    if params[:projeto] == "sem"
      scope = scope.where(project_id: nil)
    elsif params[:projeto].present?
      scope = scope.where(project_id: params[:projeto])
    end
    scope = scope.search(params[:q]) if params[:q].present?
    @total = scope.sum(:minutes)
    @entries, @pager = paginate(scope.recent)

    @business_days = (@range.first..[ @range.last, Date.current ].min).count { |d| !d.saturday? && !d.sunday? }
    @capacity = @business_days * HOURS_PER_DAY * 60
    total = base.sum(:minutes)
    in_projects = base.where.not(project_id: nil)
    @kpis = {
      total: total, people: base.distinct.count(:user_id),
      projects: in_projects.sum(:minutes), projects_count: in_projects.distinct.count(:project_id),
      other: total - in_projects.sum(:minutes),
      daily: @business_days.positive? ? total / @business_days : 0
    }
    companies = Company.where(id: base.select(:company_id)).index_by(&:id)
    by_company = base.group(:company_id).sum(:minutes).sort_by { |_, m| -m }.map { |id, m| [ companies[id], m ] }
    @by_company = by_company.first(6)
    @others = by_company.drop(6).sum(&:last)
    users = User.where(id: base.select(:user_id)).index_by(&:id)
    @by_user = base.group(:user_id).sum(:minutes).sort_by { |_, m| -m }.map { |id, m| [ users[id], m ] }
    @over_capacity = @by_user.select { |_, m| @capacity.positive? && m > @capacity }

    @users = User.where(id: policy_scope(TimeEntry).select(:user_id)).by_name
    @companies = Company.where(id: policy_scope(TimeEntry).select(:company_id)).by_name.select(:id, :trade_name)
    @projects = Project.where(id: policy_scope(TimeEntry).select(:project_id)).by_name
  end

  def new
    task = Task.find_by(id: params[:tarefa])
    ticket = Ticket.find_by(id: params[:chamado])
    project = Project.find_by(id: params[:projeto]) || task&.project
    company = project&.company || ticket&.company || Company.find_by(id: params[:empresa])
    @time_entry = authorize TimeEntry.new(user: current_user, worked_on: Date.current, company: company, project: project, task: task, ticket: ticket)
  end

  def create
    @time_entry = TimeEntry.new(entry_params)
    @time_entry.user = current_user unless policy(TimeEntry).assign_user? && @time_entry.user
    authorize @time_entry
    if @time_entry.save
      redirect_to return_path, notice: "#{hours(@time_entry.minutes)} registradas em #{@time_entry.target_name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @time_entry.update(entry_params)
      redirect_to return_path, notice: "Lançamento atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @time_entry.destroy!
    redirect_to return_path, notice: "Lançamento excluído.", status: :see_other
  end

  private

  def set_entry
    @time_entry = authorize TimeEntry.find(params[:id])
  end

  def entry_params
    permitted = %i[company_id project_id task_id ticket_id worked_on duration description]
    permitted << :user_id if policy(TimeEntry).assign_user?
    params.expect(time_entry: permitted)
  end

  # Período: mês corrente (padrão), um dos 5 meses anteriores ou o trimestre atual.
  def set_period
    months = (0..5).map { |i| Date.current.beginning_of_month << i }
    @periods = months.map { |m| [ I18n.l(m, format: "%B/%Y").capitalize, m.strftime("%Y-%m") ] } + [ [ "Trimestre atual", "trimestre" ] ]
    @period = params[:periodo].presence_in(@periods.map(&:last)) || months.first.strftime("%Y-%m")
    @range = @period == "trimestre" ? Date.current.all_quarter : Date.strptime(@period, "%Y-%m").all_month
    @period_label = @periods.to_h.invert[@period]
  end

  def hours(minutes)
    TimeEntry.format_minutes(minutes)
  end

  def return_path
    case params[:voltar]
    when "projeto" then @time_entry.project ? project_path(@time_entry.project, aba: "horas") : time_entries_path
    when "chamado" then @time_entry.ticket ? ticket_path(@time_entry.ticket) : time_entries_path
    when "tarefas" then tasks_path
    else time_entries_path(periodo: @time_entry.worked_on&.strftime("%Y-%m"))
    end
  end
end
