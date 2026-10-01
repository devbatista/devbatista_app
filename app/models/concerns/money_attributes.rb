# Valores em reais no formulário, guardados em centavos (inteiro) no banco.
#
#   money_attribute :price   # price / price= sobre price_cents
module MoneyAttributes
  extend ActiveSupport::Concern

  class_methods do
    def money_attribute(*names)
      names.each do |name|
        define_method(name) do
          cents = public_send("#{name}_cents")
          cents && cents / 100.0
        end

        define_method("#{name}=") do |value|
          public_send("#{name}_cents=", MoneyAttributes.to_cents(value))
        end
      end
    end
  end

  # Aceita 1500, "1500", "1.500,00", "1500.5" e "R$ 1.500,50".
  def self.to_cents(value)
    return nil if value.blank?
    return (value * 100).round if value.is_a?(Numeric)

    text = value.to_s.gsub(/[^\d,.-]/, "")
    text = text.delete(".").tr(",", ".") if text.include?(",")
    (BigDecimal(text) * 100).round
  rescue ArgumentError
    nil
  end
end
