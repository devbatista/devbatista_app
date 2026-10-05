# Regra de despesa recorrente (RF 27): gera os títulos a pagar dos próximos períodos pela
# rotina de recorrências, como Previsto. Mudar o valor altera só os títulos futuros não pagos;
# encerrar cancela os títulos posteriores à data de encerramento.
class RecurringExpense < ApplicationRecord
  include Auditable
  include LabeledEnums
  include MoneyAttributes
  include CostCenter

  PERIOD_MONTHS = { "monthly" => 1, "quarterly" => 3, "semiannual" => 6, "annual" => 12 }.freeze

  audited area: "financeiro"
  labeled_enum :periodicity, monthly: "Mensal", quarterly: "Trimestral", semiannual: "Semestral", annual: "Anual"
  labeled_enum :status, active: "Ativa", ended: "Encerrada"
  money_attribute :amount

  belongs_to :supplier
  has_many :payables, dependent: :nullify

  validates :description, :category, :start_on, presence: true
  validates :currency, inclusion: { in: ExchangeRate::CURRENCIES.keys }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :due_day, numericality: { only_integer: true, in: 1..31 }
  validates :category, inclusion: { in: ->(_) { Setting[:expense_categories] }, message: "não está na lista de categorias" },
                       if: :will_save_change_to_category?

  before_save { self.ended_on = ended? ? (ended_on || Date.current) : nil }
  after_update :reprice_future_payables, if: -> { saved_change_to_amount_cents? || saved_change_to_currency? }
  after_update :cancel_payables_after_end, if: -> { saved_change_to_status? && ended? }

  scope :by_supplier, -> { joins(:supplier).order("suppliers.name", :description) }

  def foreign? = currency != "BRL"

  # Vencimentos de `from` até `to`, pela periodicidade e pelo dia de vencimento.
  def due_dates(from, to)
    RecurrenceRoutine.due_dates(start_on, PERIOD_MONTHS.fetch(periodicity), due_day, from, to)
  end

  # Atributos de um título a pagar gerado por esta regra.
  def payable_attributes(due_on)
    { supplier: supplier, description: "#{description} — #{I18n.l(due_on, format: '%B/%Y').capitalize}", category: category,
      company_id: company_id, cost_center: cost_center, currency: currency, due_on: due_on, competence: due_on.beginning_of_month }
      .merge(foreign? ? { original_amount_cents: amount_cents } : { amount_cents: amount_cents })
  end

  def activity_name
    "a despesa recorrente #{description} (#{supplier&.name})"
  end

  def activity_company
    company
  end

  def to_s
    description
  end

  private

  def reprice_future_payables
    payables.where(status: %w[forecast pending]).where(due_on: Date.current..).find_each do |payable|
      attrs = foreign? ? { currency: currency, original_amount_cents: amount_cents } : { currency: currency, amount_cents: amount_cents }
      payable.update!(attrs)
    end
  end

  def cancel_payables_after_end
    payables.open.where("due_on > ?", ended_on).find_each { |p| p.cancel!("Cancelado: despesa recorrente encerrada em #{I18n.l(ended_on)}.") }
  end
end
