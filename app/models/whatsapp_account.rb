# Número do WhatsApp Business conectado pelo Embedded Signup (docs/specs/whatsapp): um
# phone_number_id de uma WABA. Há suporte a várias contas: hoje o número da DevBatista, em
# coexistência com o app do celular; no futuro, números de clientes.
# O token de acesso fica criptografado (Active Record Encryption) e fora da auditoria.
class WhatsappAccount < ApplicationRecord
  include Auditable
  include LabeledEnums

  # Limite de envio da Meta: contatos novos que o número pode iniciar em 24h.
  MESSAGING_LIMITS = {
    "TIER_250" => "250", "TIER_2K" => "2.000", "TIER_10K" => "10.000",
    "TIER_100K" => "100.000", "TIER_UNLIMITED" => "Ilimitado"
  }.freeze

  audited area: "whatsapp",
          ignore: %w[access_token quality_rating messaging_limit_tier history_sync_progress last_webhook_at]
  labeled_enum :status, pending: "Conectando", connected: "Conectado", disconnected: "Desconectado"
  labeled_enum :quality_rating, { green: "Alta", yellow: "Média", red: "Baixa", unknown: "Desconhecida" }, prefix: :quality
  encrypts :access_token

  belongs_to :connected_by, class_name: "User", optional: true
  has_many :conversations, class_name: "WhatsappConversation", inverse_of: :account, dependent: :restrict_with_error
  has_many :templates, class_name: "WhatsappTemplate", inverse_of: :account, dependent: :destroy

  validates :waba_id, :phone_number_id, :display_phone_number, presence: true
  validates :phone_number_id, uniqueness: true

  # Atributos a partir de Whatsapp::Client#phone_number_details. A qualidade vem em maiúsculas
  # (GREEN, YELLOW, RED; NA ou UNKNOWN sem avaliação); o limite de envio, do portfólio.
  def self.attributes_from_phone_details(data)
    quality = data["quality_rating"].to_s.downcase
    {
      display_phone_number: data["display_phone_number"], verified_name: data["verified_name"],
      quality_rating: QUALITY_RATING_LABELS.key?(quality) ? quality : "unknown",
      messaging_limit_tier: data["whatsapp_business_manager_messaging_limit"],
      coexistence: data["is_on_biz_app"]
    }.compact
  end

  def messaging_limit_label
    MESSAGING_LIMITS.fetch(messaging_limit_tier.to_s, messaging_limit_tier.presence || "—")
  end

  def activity_name
    "a conta do WhatsApp #{self}"
  end

  def to_s
    [ verified_name.presence, display_phone_number ].compact.join(" · ")
  end
end
