# Serviço contratado: vínculo entre um cliente e um serviço do catálogo, com as
# condições daquela contratação. Origem do MRR e das recorrências (RF 16).
class CustomerService < ApplicationRecord
  include Auditable
  include LabeledEnums
  include MoneyAttributes

  # Divisor usado para mensalizar o valor no cálculo do MRR. Avulso não entra.
  MRR_DIVISOR = { "monthly" => 1, "quarterly" => 3, "semiannual" => 6, "annual" => 12, "one_off" => nil }.freeze

  audited area: "contratos", ignore: %w[mrr_cents]
  labeled_enum :recurrence, monthly: "Mensal", quarterly: "Trimestral", semiannual: "Semestral", annual: "Anual", one_off: "Avulsa"
  labeled_enum :status, active: "Ativo", suspended: "Suspenso", ended: "Encerrado"
  money_attribute :price, :mrr

  belongs_to :company
  belongs_to :service
  belongs_to :contract, optional: true

  validates :price_cents, numericality: { greater_than: 0 }
  validates :start_date, presence: true
  validates :due_day, numericality: { only_integer: true, in: 1..31 }, allow_nil: true
  validate :contract_from_same_company

  before_save :compute_mrr
  before_save :set_ended_on

  scope :recurring, -> { where.not(recurrence: "one_off") }

  # MRR calculado, nunca digitado. Só serviços ativos e recorrentes compõem o MRR.
  def self.mrr_for(price_cents, recurrence)
    divisor = MRR_DIVISOR[recurrence.to_s]
    divisor ? (price_cents.to_i / divisor.to_f).round : 0
  end

  PERIOD_MONTHS = { "monthly" => 1, "quarterly" => 3, "semiannual" => 6, "annual" => 12 }.freeze

  # Próximo vencimento a partir de `today`, pela recorrência e pelo dia de vencimento.
  # Enquanto o Financeiro não existe, é a base da "Próxima cobrança" da Visão 360º.
  def next_due_date(today = Date.current)
    months = PERIOD_MONTHS[recurrence]
    return nil unless months && active?

    day = due_day || start_date.day
    date = start_date.beginning_of_month
    date = date.next_month(months) while due_on(date, day) < [ today, start_date ].max
    due_on(date, day)
  end

  def counts_for_mrr?
    active? && !one_off?
  end

  def activity_name
    "o serviço #{service&.name} de #{company&.trade_name}"
  end

  def to_s
    "#{service&.name} · #{company&.trade_name}"
  end

  private

  def due_on(month, day)
    month.change(day: [ day, month.end_of_month.day ].min)
  end

  def compute_mrr
    self.mrr_cents = active? ? self.class.mrr_for(price_cents, recurrence) : 0
  end

  def set_ended_on
    self.ended_on ||= Date.current if ended?
  end

  def contract_from_same_company
    errors.add(:contract, "é de outra empresa") if contract && contract.company_id != company_id
  end
end
