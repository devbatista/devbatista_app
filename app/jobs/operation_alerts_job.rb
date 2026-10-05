# Rotina diária da Operação (RF 18 e 19):
# - projeto atrasado avisa o responsável e os administradores;
# - tarefa atrasada avisa o responsável pela tarefa (sem responsável, o do projeto).
# O aviso sai no primeiro dia de atraso e se repete a cada 7 dias enquanto durar.
# Idempotente: rodar duas vezes no mesmo dia não duplica alerta.
class OperationAlertsJob < ApplicationJob
  queue_as :default

  REMINDER_DAYS = 7

  def perform(today = Date.current)
    routes = Rails.application.routes.url_helpers
    admins = User.active.joins(:role).where(roles: { key: "admin" }).to_a

    Project.late(today).includes(:company, :user).find_each do |project|
      late = project.days_late(today)
      Notification.deliver!(
        kind: "project_late", level: "crit", users: [ project.user, *admins ].uniq, notifiable: project,
        title: late < REMINDER_DAYS ? "Projeto #{project.name} passou da previsão" : "Projeto #{project.name} está atrasado há #{late} dias",
        path: routes.project_path(project), dedup_key: "project-#{project.id}-#{project.due_date}-#{late / REMINDER_DAYS}"
      )
    end

    Task.late(today).includes(:user, project: :user).find_each do |task|
      late = task.days_late(today)
      Notification.deliver!(
        kind: "task_late", level: "crit", users: [ task.user || task.project.user ], notifiable: task,
        title: "Tarefa “#{task.title}” está atrasada há #{late} #{late == 1 ? 'dia' : 'dias'}",
        path: routes.tasks_path(projeto: task.project_id), dedup_key: "task-#{task.id}-#{task.due_on}-#{late / REMINDER_DAYS}"
      )
    end
  end
end
