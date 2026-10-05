# Rotina diária (sidekiq-cron, config/schedule.yml): dispara as verificações de cada módulo.
class DailyAlertsJob < ApplicationJob
  queue_as :default

  def perform
    ContractAlertsJob.perform_now
    ProposalAlertsJob.perform_now
    OperationAlertsJob.perform_now
  end
end
