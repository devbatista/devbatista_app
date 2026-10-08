class User < ApplicationRecord
  include Auditable

  # Senha com bcrypt, bloqueio após tentativas inválidas, link de redefinição de uso único
  # e expiração por inatividade (config/initializers/devise.rb).
  devise :database_authenticatable, :recoverable, :trackable, :lockable, :timeoutable, :validatable

  SESSION_TIMEOUT_RANGE = 5..720

  # Tempo sem uso até a sessão expirar, em Configurações → Geral (minutos).
  def timeout_in
    Setting[:session_timeout_minutes].to_i.clamp(SESSION_TIMEOUT_RANGE).minutes
  end

  audited area: "administracao", ignore: %w[
    encrypted_password reset_password_token reset_password_sent_at
    sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip last_sign_in_ip
    failed_attempts locked_at email_preferences
  ], activity: false

  belongs_to :role
  has_many :audit_logs, dependent: :restrict_with_error
  has_many :notifications, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :by_name, -> { order(:name) }

  delegate :admin?, :level_for, :can_read?, :can_write?, :own_only?, :can_manage?, :sees_financials?, to: :role

  # Usuário desativado não entra, mas continua nos registros históricos.
  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :deactivated
  end

  # E-mails do Devise (redefinição de senha) saem pelo Sidekiq.
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  # Custo por hora em reais no formulário; guardado em centavos.
  def hourly_cost
    hourly_cost_cents && hourly_cost_cents / 100.0
  end

  def hourly_cost=(value)
    self.hourly_cost_cents = value.presence && (BigDecimal(value.to_s.tr(",", ".")) * 100).round
  end

  # Preferência de e-mail por tipo de alerta; o padrão é receber.
  def email_for?(kind)
    email_preferences.fetch(kind.to_s, true)
  end

  def first_name
    name.to_s.split.first
  end

  def initials
    name.to_s.split.values_at(0, -1).compact.uniq.map { |part| part[0] }.join.upcase
  end

  def to_s
    name
  end
end
