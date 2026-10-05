# CSV para abrir direto no Excel em português: separador ";", vírgula decimal e BOM UTF-8.
#   CsvExport.generate([ "Cliente", "Receita" ], [ [ "ACME", 4000.0 ] ])
module CsvExport
  BOM = "﻿".freeze
  SEPARATOR = ";".freeze

  module_function

  def generate(headers, rows)
    BOM + ([ headers ] + rows).map { |row| row.map { |value| field(value) }.join(SEPARATOR) }.join("\r\n") + "\r\n"
  end

  # Centavos → "1234,56", sem separador de milhar.
  def money(cents)
    cents.nil? ? "" : format("%.2f", cents / 100.0).tr(".", ",")
  end

  def field(value)
    text =
      case value
      when nil then ""
      when Float, BigDecimal then format("%.2f", value).tr(".", ",")
      when Date then I18n.l(value)
      else value.to_s
      end
    # Evita que o Excel interprete a célula como fórmula.
    text = "'#{text}" if text.match?(/\A[=+\-@]/) && !text.match?(/\A-?\d[\d.,]*\z/)
    text.match?(/[;"\r\n]/) ? "\"#{text.gsub('"', '""')}\"" : text
  end
end
