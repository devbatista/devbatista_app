# Integração de uma aplicação com plataforma ou API externa (RF 33).
class Integration < ApplicationRecord
  include Inventory

  PLATFORMS = [ "Meta", "WhatsApp", "Twilio", "OpenAI", "Amazon SES", "Mailgun", "PayPal", "Gateway de pagamento", "API externa" ].freeze

  environment_field
  labeled_enum :status, active: "Ativa", configuring: "Em configuração", disabled: "Desativada"

  belongs_to :app

  validates :platform, :purpose, presence: true

  scope :search, lambda { |term|
    joins(:app).where("unaccent(integrations.platform) ILIKE unaccent(:q) OR unaccent(integrations.purpose) ILIKE unaccent(:q) OR unaccent(apps.name) ILIKE unaccent(:q)",
                      q: "%#{sanitize_sql_like(term.to_s.strip)}%")
  }

  def activity_name
    "a integração #{platform} de #{app&.name}"
  end

  def activity_company
    app&.company
  end

  def to_s
    [ platform, variant ].compact_blank.join(" · ")
  end
end
