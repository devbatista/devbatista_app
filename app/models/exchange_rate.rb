# Cotação de câmbio do dia (PTAX de venda do Banco Central ou informada à mão).
# É usada para estimar o valor em reais das despesas em moeda estrangeira até o pagamento
# e para gravar o valor definitivo na data do pagamento (RF 24).
class ExchangeRate < ApplicationRecord
  CURRENCIES = { "BRL" => "Real", "USD" => "Dólar americano", "EUR" => "Euro" }.freeze
  SYMBOLS = { "BRL" => "R$", "USD" => "US$", "EUR" => "€" }.freeze

  validates :currency, inclusion: { in: CURRENCIES.keys - [ "BRL" ] }
  validates :quoted_on, presence: true, uniqueness: { scope: :currency }
  validates :rate, numericality: { greater_than: 0 }

  # Cotação para a data: a guardada, senão a PTAX do Banco Central, senão a última conhecida
  # antes da data (marcada como fallback). Devolve nil se não houver nenhuma.
  def self.lookup(currency, date = Date.current)
    return if currency.blank? || currency == "BRL"

    where(currency: currency, quoted_on: date).first || fetch_and_store(currency, date) ||
      where(currency: currency, quoted_on: ..date).order(quoted_on: :desc).first&.tap { |r| r.fallback = true }
  end

  def self.rate_for(currency, date = Date.current)
    currency == "BRL" ? BigDecimal(1) : lookup(currency, date)&.rate
  end

  def self.fetch_and_store(currency, date)
    quote = Rails.cache.fetch("ptax/#{currency}/#{date}", expires_in: 1.hour, skip_nil: true) { BcbPtax.fetch(currency, date) }
    return unless quote

    find_or_create_by!(currency: currency, quoted_on: quote[:quoted_on]) { |r| r.rate = quote[:rate] }
  rescue ActiveRecord::RecordNotUnique
    find_by(currency: currency, quoted_on: quote[:quoted_on])
  end

  # Cotação de outro dia usada porque a do dia pedido não estava disponível.
  attr_accessor :fallback

  def to_s
    "#{SYMBOLS[currency]} 1 = R$ #{format('%.2f', rate).tr('.', ',')}"
  end
end
