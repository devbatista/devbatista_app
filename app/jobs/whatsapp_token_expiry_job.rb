# Rotina diária (DailyAlertsJob): a conta do WhatsApp com o token vencido fica "Reconectar
# necessário" até alguém conectar o número de novo pelo Embedded Signup. O aviso dos 7 dias antes
# aparece na tela de integração (WhatsappAccount#token_expiring?).
class WhatsappTokenExpiryJob < ApplicationJob
  queue_as :default

  def perform(now = Time.current)
    WhatsappAccount.token_expired(now).find_each do |account|
      account.update!(status: "reconnect_required")
      Rails.logger.info("[Whatsapp] token vencido: phone_number_id=#{account.phone_number_id}, aguardando reconexão")
    end
  end
end
