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

  # A tela avisa da validade do token a partir de 7 dias do fim.
  TOKEN_WARNING = 7.days
  # Status que passam a "Reconectar necessário" quando o token vence (WhatsappTokenExpiryJob).
  ACTIVE_STATUSES = %w[pending registration_pending connected].freeze

  audited area: "whatsapp",
          ignore: %w[access_token quality_rating messaging_limit_tier history_sync_progress last_webhook_at activation_error
                     templates_sync_requested_at templates_synced_at templates_sync_error]
  # Conectando: ativação em andamento (WhatsappActivationJob). Aguardando registro: número sem
  # coexistência esperando o PIN. Reconectar necessário: o token venceu.
  labeled_enum :status, pending: "Conectando", registration_pending: "Aguardando registro", connected: "Conectado",
                        reconnect_required: "Reconectar necessário", disconnected: "Desconectado"
  labeled_enum :quality_rating, { green: "Alta", yellow: "Média", red: "Baixa", unknown: "Desconhecida" }, prefix: :quality
  encrypts :access_token

  belongs_to :connected_by, class_name: "User", optional: true
  has_many :conversations, class_name: "WhatsappConversation", inverse_of: :account, dependent: :restrict_with_error
  has_many :templates, class_name: "WhatsappTemplate", inverse_of: :account, dependent: :destroy

  validates :waba_id, :phone_number_id, presence: true
  validates :phone_number_id, uniqueness: true

  scope :token_expired, ->(now = Time.current) { where(status: ACTIVE_STATUSES, token_expires_at: ..now) }

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

  # Marcas da ativação e das sincronizações, zeradas só depois de uma desconexão.
  ACTIVATION_MARKS = %i[subscribed_at registered_at contacts_sync_request_id contacts_synced_at history_sync_request_id
                        history_sync_progress history_synced_at history_sync_error].freeze

  # Atributos de uma conexão pelo Embedded Signup. Reconectar o mesmo número reaproveita o
  # registro e as conversas e recomeça a ativação. Depois de uma desconexão (no celular ou pela
  # Meta), é conexão nova, com novo prazo de 24h para as sincronizações: as marcas são zeradas
  # (reset_marks). Na renovação do token, ficam, e a ativação não pede as sincronizações de novo.
  def self.connection_attributes(token:, token_expires_at:, user:, reset_marks:)
    attributes = { access_token: token, token_expires_at: token_expires_at, connected_by: user, connected_at: Time.current,
                   status: "pending", disconnected_at: nil, disconnect_reason: nil, activation_error: nil }
    reset_marks ? attributes.merge(ACTIVATION_MARKS.index_with(nil)) : attributes
  end

  # Alguma sincronização com o app do celular já chegou pelo webhook.
  def sync_received?
    contacts_synced_at.present? || history_synced_at.present? || history_sync_progress.present?
  end

  def messaging_limit_label
    MESSAGING_LIMITS.fetch(messaging_limit_tier.to_s, messaging_limit_tier.presence || "—")
  end

  def token_expired?(now = Time.current)
    token_expires_at.present? && token_expires_at <= now
  end

  def token_expiring?(now = Time.current)
    token_expires_at.present? && !token_expired?(now) && token_expires_at <= now + TOKEN_WARNING
  end

  # Templates só sincronizam com o acesso à Meta válido.
  def templates_syncable?
    ACTIVE_STATUSES.include?(status)
  end

  def templates_sync_blocked_reason
    case status
    when "disconnected" then "O número está desconectado. Conecte de novo em Integrações → WhatsApp para sincronizar e criar templates."
    when "reconnect_required" then "O acesso à Meta venceu. Reconecte o número em Integrações → WhatsApp para sincronizar e criar templates."
    end
  end

  # Sincronização pedida pela tela e ainda sem resultado.
  def templates_syncing?
    templates_sync_requested_at.present? && templates_sync_error.blank? &&
      (templates_synced_at.nil? || templates_synced_at < templates_sync_requested_at)
  end

  # Falha definitiva da ativação, com a mensagem em português para a tela.
  def fail_activation!(error)
    update!(activation_error: error.user_message.to_s.truncate(255))
  end

  def activity_name
    "a conta do WhatsApp #{self}"
  end

  def to_s
    [ verified_name.presence, display_phone_number.presence ].compact.join(" · ").presence || "Número #{phone_number_id}"
  end
end
