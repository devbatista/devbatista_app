# Webhook da Cloud API do WhatsApp (docs/specs/whatsapp). Herda de ActionController::API: fica
# fora do login, do Pundit, do bloqueio de navegadores e do CSRF, que barrariam a Meta.
#
#   GET  verificação, ao configurar o webhook no app da Meta (hub.mode, hub.verify_token, hub.challenge)
#   POST eventos, assinados com o app secret no X-Hub-Signature-256 (HMAC-SHA256 do corpo cru).
#        Responde 200 logo e processa cada mudança num job; a Meta reenvia por até 7 dias o que
#        não receber 200, e o processamento ignora o que já entrou.
module Webhooks
  class WhatsappController < ActionController::API
    def verify
      token = Whatsapp.config.webhook_verify_token.to_s
      if params["hub.mode"] == "subscribe" && token.present? && ActiveSupport::SecurityUtils.secure_compare(params["hub.verify_token"].to_s, token)
        render plain: params["hub.challenge"].to_s
      else
        head :forbidden
      end
    end

    def receive
      payload = request.raw_post
      return head(:unauthorized) unless valid_signature?(payload)

      data = JSON.parse(payload)
      return head(:ok) unless data["object"] == "whatsapp_business_account"

      Array(data["entry"]).each do |entry|
        Array(entry["changes"]).each do |change|
          WhatsappWebhookJob.perform_later(entry["id"].to_s, change["field"].to_s, change["value"] || {}, entry["time"])
        end
      end
      head :ok
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def valid_signature?(payload)
      secret = Whatsapp.config.app_secret.to_s
      if secret.blank?
        Rails.logger.error("[Whatsapp] META_APP_SECRET não configurado: webhook recusado")
        return false
      end

      expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, payload)}"
      ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Hub-Signature-256"].to_s)
    end
  end
end
