# Rotina diária (DailyAlertsJob) do acesso à Meta de cada número do WhatsApp:
# - avisa na central de notificações 7 dias antes do vencimento do token (atenção) e no dia
#   (crítico), uma vez por conta e data de vencimento, mesmo que a rotina rode duas vezes;
# - a conta com o token vencido fica "Reconectar necessário" até alguém conectar o número de novo
#   pelo Embedded Signup.
# A tela de integração também mostra o aviso dos 7 dias (WhatsappAccount#token_expiring?).
class WhatsappTokenExpiryJob < ApplicationJob
  queue_as :default

  WARNING_DAYS = 7

  def perform(now = Time.current)
    today = now.to_date
    WhatsappAccount.where(status: WhatsappAccount::ACTIVE_STATUSES).where(token_expires_at: today.beginning_of_day..(today + WARNING_DAYS).end_of_day)
                   .find_each { |account| warn_expiry(account, today) }

    WhatsappAccount.token_expired(now).find_each do |account|
      account.update!(status: "reconnect_required")
      Rails.logger.info("[Whatsapp] token vencido: phone_number_id=#{account.phone_number_id}, aguardando reconexão")
    end
  end

  private

  # Entre 7 e 1 dia antes, o aviso de atenção (se a rotina falhar no 7º dia, avisa no seguinte); no
  # dia, o crítico.
  def warn_expiry(account, today)
    expires_on = account.token_expires_at.to_date
    name = account.to_s
    if expires_on == today
      deliver(account, "dia", "crit", "O acesso do WhatsApp de #{name} vence hoje. Conecte o número de novo para continuar enviando.")
    else
      days = (expires_on - today).to_i
      deliver(account, "aviso", "warn", "O acesso do WhatsApp de #{name} vence em #{days} #{days == 1 ? 'dia' : 'dias'} (#{I18n.l(expires_on, format: '%d/%m/%Y')}).")
    end
  end

  def deliver(account, stage, level, title)
    Notification.deliver!(kind: "whatsapp_token_expiring", title: title, level: level, notifiable: account,
                          path: Rails.application.routes.url_helpers.whatsapp_accounts_path,
                          dedup_key: "whatsapp_token:#{account.id}:#{account.token_expires_at.to_date.iso8601}:#{stage}")
  end
end
