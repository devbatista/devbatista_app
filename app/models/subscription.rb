# Assinatura de um produto próprio (RF 35), lançada e atualizada à mão no MVP: não há
# sincronização com checkout nem gateway. Ativas e inadimplentes compõem o MRR e os clientes.
class Subscription < ApplicationRecord
  include Auditable
  include LabeledEnums
  include MoneyAttributes

  PLANS = [ "Essencial", "Profissional", "Equipe", "Beta fechado" ].freeze

  audited area: "produtos"
  labeled_enum :status, trial: "Em teste", active: "Ativa", delinquent: "Inadimplente", cancelled: "Cancelada"
  money_attribute :monthly_value

  belongs_to :product
  belongs_to :company, optional: true

  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :subscriber_name, :plan, :started_on, presence: true
  validates :monthly_value_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_save { self.cancelled_on = cancelled? ? (cancelled_on || Date.current) : nil }

  scope :search, lambda { |term|
    where("unaccent(subscriptions.subscriber_name) ILIKE unaccent(:q) OR subscriptions.email ILIKE :q", q: "%#{sanitize_sql_like(term.to_s.strip)}%")
  }

  # Conta no MRR e nos clientes na data: hoje, as ativas e as inadimplentes (seguem assinantes
  # até o cancelamento); no passado, as que já tinham começado (fora do teste) e ainda não
  # tinham sido canceladas.
  def counts_on?(date)
    return active? || delinquent? if date >= Date.current

    started_on <= date && (trial_ends_on.nil? || trial_ends_on <= date) && !trial? && (cancelled_on.nil? || cancelled_on > date)
  end

  def activity_name
    "a assinatura de #{subscriber_name} (#{product&.name})"
  end

  def to_s
    "#{subscriber_name} · #{product&.name}"
  end
end
