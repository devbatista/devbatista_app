# Rotina diária de recorrências (sidekiq-cron às 06:00, config/schedule.yml).
class RecurrenceJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    RecurrenceRoutine.new(today).run!
  end
end
