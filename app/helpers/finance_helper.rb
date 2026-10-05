module FinanceHelper
  TITLE_TONES = { "forecast" => "info", "pending" => "warn", "paid" => "good", "overdue" => "crit", "cancelled" => "mute" }.freeze
  INVOICE_TONES = { "pending" => "warn", "issued" => "good", "cancelled" => "mute" }.freeze

  def title_badge(title)
    status_badge(title.status_label, TITLE_TONES[title.status])
  end

  def invoice_badge(invoice)
    status_badge(invoice.status_label, INVOICE_TONES[invoice.status])
  end

  # Valor na moeda original: "US$ 20,00".
  def money_in(cents, currency)
    return brl(cents) if currency == "BRL"

    number_to_currency(cents / 100.0, unit: ExchangeRate::SYMBOLS[currency], separator: ",", delimiter: ".", format: "%u %n", precision: 2)
  end

  # Valor da despesa em reais, com "≈" enquanto estimado e o valor original embaixo.
  def payable_amount(payable, rate: true)
    return brl(payable.amount_cents) unless payable.foreign?

    sub = money_in(payable.original_amount_cents, payable.currency)
    sub += " · câmbio #{number_with_precision(payable.exchange_rate, precision: 2, separator: ',')}" if rate && payable.paid? && payable.exchange_rate
    sub += " · câmbio de hoje" if rate && payable.estimated?
    safe_join([ "#{'≈ ' if payable.estimated?}#{number_to_currency(payable.amount_cents / 100.0, unit: 'R$', separator: ',', delimiter: '.', format: '%u %n', precision: 2)}",
                tag.span(sub, class: "cell-sub") ])
  end

  # Valores do gráfico em R$ mil: 41_200_00 → "41,2".
  def thousands(cents)
    number_with_precision(cents / 100_000.0, precision: 1, separator: ",", delimiter: ".")
  end

  def days_text(days)
    "#{days} #{days == 1 ? 'dia' : 'dias'}"
  end

  # "amanhã", "hoje", "em 3 dias"
  def due_hint(date, today = Date.current)
    days = (date - today).to_i
    return "hoje" if days.zero?
    return "amanhã" if days == 1

    days.positive? ? "em #{days} dias" : "há #{-days} dias"
  end
end
