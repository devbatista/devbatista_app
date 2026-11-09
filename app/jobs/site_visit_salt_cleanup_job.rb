# Rotina diária (sidekiq-cron às 00:10, config/schedule.yml): apaga os sais dos dias anteriores.
# Sem o sal, o hash de ontem não pode ser refeito, e o visitante de ontem não é reconhecido hoje.
class SiteVisitSaltCleanupJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    SiteVisitSalt.where(day: ...today).delete_all
  end
end
