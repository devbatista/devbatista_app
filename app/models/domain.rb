# Domínio de um cliente (RF 31). Alertas a 60, 30 e 7 dias do vencimento (DomainAlertsJob,
# prazos em Configurações); sem renovação automática tem destaque na lista.
class Domain < ApplicationRecord
  include Inventory
  include MoneyAttributes

  REGISTRARS = %w[Registro.br Cloudflare GoDaddy Hostinger].freeze

  labeled_enum :paid_by, { devbatista: "DevBatista", client: "Cliente" }, prefix: :paid_by
  money_attribute :renewal_cost

  belongs_to :company

  normalizes :name, with: ->(value) { value.to_s.strip.downcase.sub(%r{\Ahttps?://}, "").sub(/\Awww\./, "").delete_suffix("/") }

  validates :name, presence: true, uniqueness: { message: "já cadastrado" }, format: { with: /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/, message: "não parece um domínio" }
  validates :registrar, :expires_on, presence: true
  validates :currency, inclusion: { in: ExchangeRate::CURRENCIES.keys }

  scope :by_expiration, -> { order(:expires_on) }
  scope :expiring_within, ->(days, today = Date.current) { where(expires_on: today..(today + days)) }
  scope :search, ->(term) { joins(:company).where("domains.name ILIKE :q OR unaccent(companies.trade_name) ILIKE unaccent(:q)", q: "%#{sanitize_sql_like(term.to_s.strip)}%") }

  def days_left(today = Date.current)
    (expires_on - today).to_i
  end

  # Faixa de alerta pelo prazo configurado (ex.: 7, 30 ou 60 dias), ou nil se está em dia.
  def alert_window(today = Date.current, windows = Setting[:domain_alert_days].map(&:to_i).sort)
    left = days_left(today)
    windows.find { |d| left <= d } if left >= 0
  end

  def expired?(today = Date.current) = expires_on < today

  # Pede atenção: venceu ou está numa faixa de alerta.
  def attention?(today = Date.current, windows = Setting[:domain_alert_days].map(&:to_i).sort)
    expired?(today) || alert_window(today, windows).present?
  end

  def renewal_cost_brl_cents
    (renewal_cost_cents * (ExchangeRate.rate_for(currency) || 0)).round
  end

  # Renovação registrada: novo vencimento, custo e renovação automática.
  def renew!(expires_on:, cost: nil, auto_renew: nil, notes: nil)
    self.expires_on = expires_on
    self.renewal_cost = cost if cost.present?
    self.auto_renew = auto_renew unless auto_renew.nil?
    self.notes = [ self.notes, notes ].compact_blank.join("\n").presence
    save!
  end

  def activity_name
    "o domínio #{name}"
  end

  def to_s
    name
  end
end
