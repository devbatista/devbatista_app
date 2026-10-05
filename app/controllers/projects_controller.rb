class ProjectsController < ApplicationController
  before_action :set_project, only: %i[show edit update destroy]

  def index
    authorize Project
    scope = policy_scope(Project).joins(:company).includes(:company, :user, :contract, :proposal)
    @counts = scope.group(:status).count
    scope = scope.where(status: params[:status]) if Project.statuses.key?(params[:status])
    scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
    scope = scope.where(user_id: params[:responsavel]) if params[:responsavel].present?
    scope = scope.late if params[:atrasados] == "1"
    scope = scope.search(params[:q]) if params[:q].present?
    scope = apply_sort(scope, {
      "previsao" => [ "Previsão mais próxima", ->(s) { s.order(Arel.sql("projects.status IN ('done','cancelled')"), :due_date) } ],
      "inicio" => [ "Início mais recente", ->(s) { s.order(Arel.sql("projects.start_date DESC NULLS LAST"), id: :desc) } ],
      "cliente" => [ "Cliente", ->(s) { s.order("companies.trade_name", :due_date) } ],
      "orcamento" => [ "Maior orçamento", ->(s) { s.order(budget_cents: :desc) } ]
    })
    @projects, @pager = paginate(scope)
    ids = @projects.map(&:id)
    @hours = TimeEntry.where(project_id: ids).group(:project_id).sum(:minutes)
    @estimates = Task.where(project_id: ids).group(:project_id).sum(:estimated_minutes)
    @companies = Company.where(id: Project.select(:company_id)).by_name.select(:id, :trade_name)
    @users = User.where(id: Project.select(:user_id)).by_name
    @late = Project.late.includes(:company, :user).order(:due_date).to_a
    month = Date.current.all_month
    project_hours = TimeEntry.where.not(project_id: nil).where(worked_on: month)
    @kpis = {
      active: Project.active.count,
      budget: Project.active.sum(:budget_cents),
      hours_month: project_hours.sum(:minutes),
      projects_month: project_hours.distinct.count(:project_id)
    }
  end

  def show
    @tasks = @project.tasks.includes(:user).by_due.to_a
    @logged_by_task = TimeEntry.where(task_id: @tasks.map(&:id)).group(:task_id).sum(:minutes)
    @logged = @project.logged_minutes
    @estimated = @tasks.sum { |t| t.estimated_minutes.to_i }
    @month_minutes = @project.time_entries.where(worked_on: Date.current.all_month).sum(:minutes)
    users = User.where(id: @project.time_entries.select(:user_id)).index_by(&:id)
    @hours_by_user = @project.time_entries.group(:user_id).sum(:minutes).sort_by { |_, m| -m }.map { |id, m| [ users[id], m ] }
    @entries = policy_scope(TimeEntry).where(project: @project).includes(:user, :task, :ticket).recent.limit(50)
    @documents = policy(Document).index? ? @project.documents.includes(:uploaded_by, file_attachment: :blob).recent : Document.none
    @activities = Activity.where(subject_type: "Project", subject_id: @project.id)
                          .or(Activity.where(subject_type: "Task", subject_id: @tasks.map(&:id)))
                          .or(Activity.where(subject_type: "TimeEntry", subject_id: @project.time_entries.select(:id)))
                          .includes(:user).recent.limit(50)
  end

  def new
    @project = authorize Project.new(company_id: params[:empresa], user: current_user, status: "planning",
                                     start_date: Date.current, due_date: Date.current + 60, progress_from_tasks: true)
  end

  def create
    @project = authorize Project.new(project_params)
    if @project.save
      redirect_to @project, notice: "Projeto cadastrado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Projeto atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @project.destroy
      redirect_to projects_path, notice: "Projeto excluído.", status: :see_other
    else
      redirect_to @project, alert: "Não foi possível excluir: #{@project.errors.full_messages.to_sentence}."
    end
  end

  private

  def set_project
    @project = authorize Project.find(params[:id])
  end

  def project_params
    params.expect(project: %i[company_id name description user_id status start_date due_date budget progress progress_from_tasks contract_id proposal_id])
  end
end
