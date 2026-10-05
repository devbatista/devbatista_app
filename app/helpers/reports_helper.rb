# Formatação das células dos relatórios pelo tipo da coluna (ReportCatalog::Column).
module ReportsHelper
  def report_cell(value, type)
    return tag.span("—", class: "muted") if value.nil? || value == ""

    case type
    when :money then brl(value)
    when :count then number_with_delimiter(value, delimiter: ".")
    when :hours then hours_br(value)
    when :percent then percent_br(value)
    when :date then date_br(value)
    else value
    end
  end

  def report_numeric?(type) = type != :text && type != :date

  # Valor curto ao lado das barras do gráfico.
  def report_chart_value(type)
    case type
    when :money then ->(v) { thousands(v) }
    when :hours then ->(v) { hours_br(v) }
    when :percent then ->(v) { percent_br(v) }
    else ->(v) { v.to_s }
    end
  end

  def report_chart_tip(type)
    type == :money ? ->(v) { brl(v) } : report_chart_value(type)
  end
end
