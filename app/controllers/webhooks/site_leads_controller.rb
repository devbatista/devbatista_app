# Leads do site (devbatista.com): Diagnóstico Tecnológico e e-book (SiteLeadCapture). Herda de
# ActionController::API, como o webhook do WhatsApp: fica fora do login, do Pundit e do CSRF.
# Quem chama é o PHP do site, servidor a servidor, com o SITE_LEADS_TOKEN no Authorization: Bearer.
#
#   POST JSON  201 lead criado · 200 lead em aberto completado · 401 token errado · 422 dados inválidos
module Webhooks
  class SiteLeadsController < ActionController::API
    def create
      return head(:unauthorized) unless valid_token?

      attributes = SiteLeadCapture.attribute_names
      capture = SiteLeadCapture.new(params.slice(*attributes).permit(*attributes))
      if capture.save
        render json: { id: capture.lead.id, created: capture.created? }, status: capture.created? ? :created : :ok
      else
        render json: { errors: capture.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def valid_token?
      token = Rails.configuration.x.site_leads.token.to_s
      if token.blank?
        Rails.logger.error("[SiteLeads] SITE_LEADS_TOKEN não configurado: lead do site recusado")
        return false
      end

      ActiveSupport::SecurityUtils.secure_compare(request.authorization.to_s, "Bearer #{token}")
    end
  end
end
