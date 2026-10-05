# Serviço externo (RF 34): SaaS ou infraestrutura de terceiros usado por um cliente, com custo
# na moeda original, periodicidade e quem paga. Só os pagos pela DevBatista entram no custo
# direto do cliente; o valor em reais usa a PTAX do dia (ExchangeRate).
class ExternalService < ApplicationRecord
  include Inventory
  include MoneyAttributes

  # Equivalente mensal: anual ÷ 12; por consumo usa o valor da última fatura.
  MONTHS = { "monthly" => 1, "annual" => 12, "usage" => 1 }.freeze

  labeled_enum :periodicity, monthly: "Mensal", annual: "Anual", usage: "Por consumo"
  labeled_enum :paid_by, { devbatista: "DevBatista", client: "Cliente" }, prefix: :paid_by
  money_attribute :cost

  belongs_to :supplier
  belongs_to :company
  belongs_to :app, optional: true
  has_many :payables, dependent: :nullify
  has_many :recurring_expenses, dependent: :nullify
  has_many :hosted_apps, class_name: "App", as: :hosting, dependent: :nullify

  validates :name, presence: true
  validates :currency, inclusion: { in: ExchangeRate::CURRENCIES.keys }
  validates :cost_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :app_from_same_company

  scope :active, -> { where(active: true) }
  scope :by_name, -> { order(:name) }
  scope :search, lambda { |term|
    joins(:supplier).where("unaccent(external_services.name) ILIKE unaccent(:q) OR unaccent(suppliers.name) ILIKE unaccent(:q)",
                           q: "%#{sanitize_sql_like(term.to_s.strip)}%")
  }

  def foreign? = currency != "BRL"

  # Equivalente mensal em reais, pela cotação do dia para moeda estrangeira.
  def monthly_brl_cents(rate = nil)
    rate ||= ExchangeRate.rate_for(currency) || 0
    (cost_cents * rate / MONTHS.fetch(periodicity)).round
  end

  def hosting_label = "#{name} · #{company&.trade_name}"

  def activity_name
    "o serviço externo #{name} de #{company&.trade_name}"
  end

  def to_s
    plan.present? ? "#{name} — #{plan}" : name
  end

  private

  def app_from_same_company
    errors.add(:app, "é de outro cliente") if app && app.company_id != company_id
  end
end
