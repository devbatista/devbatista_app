# Rotina diária (sidekiq-cron às 05:30, config/schedule.yml): puxa as faturas das conexões de
# cobrança ativas antes da rotina de recorrências, que marca os vencidos às 06:00.
# Com uma conexão, sincroniza só ela (botão "Sincronizar agora").
class BillingSyncJob < ApplicationJob
  queue_as :default

  def perform(connection_id = nil, today = Date.current)
    if connection_id
      Billing::Sync.new(BillingConnection.find(connection_id), today: today).run
    else
      Billing::Sync.run_all(today)
    end
  end
end
