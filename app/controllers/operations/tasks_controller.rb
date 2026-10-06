module Operations
  class TasksController < ApplicationController
    before_action :set_task, only: %i[edit update destroy move]

    # No quadro, a coluna Concluída mostra só as tarefas concluídas nos últimos 14 dias.
    DONE_DAYS = 14

    def index
      authorize Task
      @mode = params[:modo] == "lista" ? "lista" : "quadro"
      scope = policy_scope(Task).joins(project: :company).includes(:user, project: :company)
      scope = scope.where(project_id: params[:projeto]) if params[:projeto].present?
      scope = scope.where(user_id: params[:responsavel]) if params[:responsavel].present?
      scope = scope.where(priority: params[:prioridade]) if Task.priorities.key?(params[:prioridade])
      scope = scope.late if params[:atrasadas] == "1"
      scope = scope.search(params[:q]) if params[:q].present?
      @counts = scope.group(:status).count

      if @mode == "lista"
        scope = scope.where(status: params[:status]) if Task.statuses.key?(params[:status])
        scope = apply_sort(scope, {
          "prazo" => [ "Prazo mais próximo", ->(s) { s.order(Arel.sql("tasks.status = 'done'")).by_due } ],
          "prioridade" => [ "Prioridade", ->(s) { s.in_order_of(:priority, %w[urgent high normal low]).by_due } ],
          "projeto" => [ "Projeto", ->(s) { s.order("projects.name").by_due } ]
        })
        @tasks, @pager = paginate(scope)
      else
        recent_done = scope.where(status: "done", completed_on: (Date.current - DONE_DAYS)..)
        @tasks = scope.pending.or(recent_done).by_due.to_a
        @lanes = Task::STATUS_LABELS.map do |key, label|
          tasks = @tasks.select { |t| t.status == key }
          tasks = tasks.sort_by { |t| [ -t.completed_on.jd, t.id ] } if key == "done"
          { key: key, label: label, tasks: tasks }
        end
        @done_total = @counts["done"].to_i
      end
      @logged = TimeEntry.where(task_id: @tasks.map(&:id)).group(:task_id).sum(:minutes)
      @projects = Project.where(id: Task.select(:project_id)).includes(:company).by_name
      @users = User.where(id: Task.select(:user_id)).by_name
      @project = @projects.find { |p| p.id.to_s == params[:projeto] } if params[:projeto].present?
    end

    def new
      status = params[:status].presence_in(Task.statuses.keys) || "backlog"
      @task = authorize Task.new(project_id: params[:projeto], status: status, priority: "normal")
    end

    def create
      @task = authorize Task.new(task_params)
      if @task.save
        redirect_to return_path, notice: "Tarefa “#{@task.title}” criada."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @logged = @task.time_entries.sum(:minutes)
    end

    def update
      if @task.update(task_params)
        redirect_to return_path, notice: "Tarefa atualizada."
      else
        @logged = @task.time_entries.sum(:minutes)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @task.destroy!
      redirect_to return_path, notice: "Tarefa excluída.", status: :see_other
    end

    # Arrastar o cartão no quadro muda o status.
    def move
      to = params[:to].to_s
      if Task.statuses.key?(to) && @task.update(status: to)
        respond_to do |format|
          format.json { render json: { ok: true, label: @task.status_label } }
          format.html { redirect_back fallback_location: tasks_path, notice: "Tarefa movida para #{@task.status_label}." }
        end
      else
        message = @task.errors.full_messages.to_sentence.presence || "Status inválido."
        respond_to do |format|
          format.json { render json: { ok: false, error: message }, status: :unprocessable_entity }
          format.html { redirect_back fallback_location: tasks_path, alert: message }
        end
      end
    end

    private

    def set_task
      @task = Task.find(params[:id])
      authorize @task, action_name == "move" ? :update? : "#{action_name}?"
    end

    def task_params
      params.expect(task: %i[project_id title description user_id status priority due_on estimated_hours])
    end

    def return_path
      params[:voltar] == "projeto" && @task.project ? project_path(@task.project, aba: "tarefas") : tasks_path(modo: params[:modo].presence_in(%w[lista]))
    end
  end
end
