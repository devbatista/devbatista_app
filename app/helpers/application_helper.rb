module ApplicationHelper
  # Formatos da interface (docs/design/DESIGN-SYSTEM.md → Textos e formatos).
  def brl(cents)
    return "—" if cents.nil?

    value = cents / 100.0
    precision = (cents % 100).zero? ? 0 : 2
    number_to_currency(value, unit: "R$", separator: ",", delimiter: ".", format: "%u %n", precision: precision)
  end

  def date_br(value)
    value ? l(value.to_date, format: "%d/%m/%Y") : "—"
  end

  def datetime_br(value)
    value ? l(value, format: "%d/%m/%Y %H:%M") : "—"
  end

  def status_badge(label, tone)
    tag.span(label, class: "badge b-#{tone}")
  end

  def page_title(title)
    content_for(:title, title)
  end
end
