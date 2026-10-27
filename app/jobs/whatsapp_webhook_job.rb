# Processa uma mudança do webhook do WhatsApp (Webhooks::WhatsappController) fora da requisição,
# com Whatsapp::WebhookProcessor. Pode rodar de novo sem duplicar nada.
#
# Status que chega antes de a mensagem enviada ser gravada: tenta de novo algumas vezes e,
# se a mensagem não aparecer (enviada por fora do Admin), desiste sem erro.
#
# O argumento é o payload da Meta (texto das mensagens, telefones, nomes): não vai para o log
# do Active Job e, se o job falhar, o Sidekiq também o omite (config/initializers/sidekiq.rb).
class WhatsappWebhookJob < ApplicationJob
  self.log_arguments = false

  queue_as :default

  retry_on Whatsapp::WebhookProcessor::StatusTargetMissing, wait: 15.seconds, attempts: 4 do |_job, error|
    Rails.logger.info("[Whatsapp] #{error.message}; desistindo")
  end

  def perform(entry_id, field, value, time = nil)
    Whatsapp::WebhookProcessor.new(entry_id: entry_id, field: field, value: value, time: time).call
  end
end
