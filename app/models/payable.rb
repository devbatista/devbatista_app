# Despesa e conta a pagar num registro só (RF 24 e 26). Despesas lista por competência, Contas
# a pagar por vencimento. Centro de custo é uma área interna ou um cliente; com cliente, a
# despesa entra no custo direto dele.
#
# Em moeda estrangeira guarda o valor original, a moeda e o valor em reais. Até o pagamento o
# valor em reais é estimado pela PTAX do dia (ExchangeRate); no pagamento vira definitivo.
class Payable < ApplicationRecord
  include FinancialTitle
  include CostCenter

  audited area: "financeiro"
  money_attribute :original_amount

  belongs_to :supplier
  belongs_to :recurring_expense, optional: true

  validates :currency, inclusion: { in: ExchangeRate::CURRENCIES.keys }
  validates :original_amount_cents, presence: { message: "é obrigatório em moeda estrangeira" }, if: :foreign?
  validates :category, inclusion: { in: ->(_) { Setting[:expense_categories] }, message: "não está na lista de categorias" },
                       if: :will_save_change_to_category?

  before_validation { self.category = supplier&.category if category.blank? }
  before_validation { self.original_amount_cents = nil unless foreign? }
  before_validation :estimate_amount, if: :needs_estimate?

  scope :search, lambda { |term|
    joins(:supplier).where("unaccent(payables.description) ILIKE unaccent(:q) OR unaccent(suppliers.name) ILIKE unaccent(:q)",
                           q: "%#{sanitize_sql_like(term.to_s.strip)}%")
  }
  scope :foreign, -> { where.not(currency: "BRL") }

  def foreign? = currency.present? && currency != "BRL"

  # Valor em reais ainda estimado pelo câmbio do dia (≈).
  def estimated? = foreign? && !paid?

  def recurring? = recurring_expense_id.present?

  def currency_symbol = ExchangeRate::SYMBOLS[currency]

  # Pagamento: em moeda estrangeira, o câmbio vem da PTAX da data do pagamento, a menos que
  # seja informado (ou que o valor em reais seja informado, ex.: fatura do cartão com IOF).
  def register_payment!(paid_on:, original_amount: nil, rate: nil, amount: nil, notes: nil)
    self.paid_on = paid_on
    self.notes = [ self.notes, notes ].compact_blank.join("\n").presence
    if foreign?
      self.original_amount = original_amount if original_amount.present?
      rate = rate.present? ? BigDecimal(rate.to_s.tr(",", ".")) : nil
      rate ||= ExchangeRate.rate_for(currency, paid_on) if amount.blank?
      self.amount = amount.presence || (rate && (original_amount_cents * rate / 100.0).round(2))
      self.exchange_rate = rate || (amount_cents.to_f / original_amount_cents if original_amount_cents.to_i.positive?)
      errors.add(:base, "Sem cotação do #{currency} para #{I18n.l(paid_on)}: informe o câmbio ou o valor em reais") and return false if amount_cents.nil?
    else
      self.amount = amount if amount.present?
    end
    save
  end

  # Recalcula a estimativa em reais com a cotação do dia (rotina diária).
  def refresh_estimate!(today = Date.current)
    rate = ExchangeRate.rate_for(currency, today)
    return false unless estimated? && rate

    cents = (original_amount_cents * rate).round
    cents == amount_cents ? false : update!(amount_cents: cents, exchange_rate: rate)
  end

  def activity_name
    "a despesa #{description} (#{supplier&.name})"
  end

  def activity_company
    company
  end

  def to_s
    description
  end

  private

  # Estima o valor em reais quando não foi informado ou quando o valor original mudou sozinho.
  def needs_estimate?
    return false unless foreign? && !paid?

    amount_cents.nil? || ((will_save_change_to_original_amount_cents? || will_save_change_to_currency?) && !will_save_change_to_amount_cents?)
  end

  def estimate_amount
    rate = ExchangeRate.rate_for(currency, Date.current)
    if rate
      self.exchange_rate = rate
      self.amount_cents = (original_amount_cents.to_i * rate).round
    elsif amount_cents.nil?
      errors.add(:amount, "não pôde ser estimado: sem cotação do #{currency}. Informe o valor em reais")
    end
  end
end
