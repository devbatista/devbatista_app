# Rotina diária (sidekiq-cron às 04:00, config/schedule.yml) e sob demanda, quando falta no cache a
# faixa de IP de algum robô de IA: baixa as faixas oficiais publicadas (config/ai_agents.yml).
class AiAgentIpRangesJob < ApplicationJob
  queue_as :default

  def perform
    SiteVisits::AiAgentIpRanges.refresh_all
  end
end
