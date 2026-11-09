# Visitas do site (devbatista.com, docs/specs/visitas-do-site): páginas vistas, saídas e acessos de
# robôs e agentes de IA. Herda de ActionController::API, como o webhook de leads: fica fora do
# login, do Pundit e do CSRF. Quem chama é o PHP do site, servidor a servidor, com o
# SITE_VISITS_TOKEN no Authorization: Bearer; o navegador nunca fala direto com o Admin.
#
#   POST JSON  202 aceito ou descartado de propósito · 401 token errado · 422 dados inválidos
module Webhooks
  class SiteVisitsController < ActionController::API
    MAX_BODY = 16.kilobytes

    def create
      return head(:unauthorized) unless valid_token?
      return render(json: { errors: [ "corpo maior que #{MAX_BODY / 1024} KB" ] }, status: :unprocessable_entity) if request.raw_post.bytesize > MAX_BODY

      payload = JSON.parse(request.raw_post)
      return render(json: { errors: [ "o corpo precisa ser um objeto JSON" ] }, status: :unprocessable_entity) unless payload.is_a?(Hash)

      SiteVisits::Tracker.new(payload).track
      head :accepted
    rescue JSON::ParserError
      render json: { errors: [ "JSON inválido" ] }, status: :unprocessable_entity
    rescue SiteVisits::Tracker::Invalid => e
      render json: { errors: [ e.message ] }, status: :unprocessable_entity
    end

    private

    def valid_token?
      token = Rails.configuration.x.site_visits.token.to_s
      if token.blank?
        Rails.logger.error("[SiteVisits] SITE_VISITS_TOKEN não configurado: visita do site recusada")
        return false
      end

      ActiveSupport::SecurityUtils.secure_compare(request.authorization.to_s, "Bearer #{token}")
    end
  end
end
