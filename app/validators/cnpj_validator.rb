# Valida os dígitos verificadores do CNPJ (RF 12).
#   validates :cnpj, cnpj: true
class CnpjValidator < ActiveModel::EachValidator
  WEIGHTS_1 = [ 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze
  WEIGHTS_2 = [ 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze

  def self.valid?(value)
    digits = value.to_s.gsub(/\D/, "")
    return false unless digits.size == 14 && digits.squeeze.size > 1

    numbers = digits.chars.map(&:to_i)
    check_digit(numbers[0, 12], WEIGHTS_1) == numbers[12] &&
      check_digit(numbers[0, 13], WEIGHTS_2) == numbers[13]
  end

  def self.check_digit(numbers, weights)
    rest = numbers.zip(weights).sum { |n, w| n * w } % 11
    rest < 2 ? 0 : 11 - rest
  end

  def self.format(value)
    digits = value.to_s.gsub(/\D/, "")
    return value unless digits.size == 14

    "#{digits[0, 2]}.#{digits[2, 3]}.#{digits[5, 3]}/#{digits[8, 4]}-#{digits[12, 2]}"
  end

  def validate_each(record, attribute, value)
    record.errors.add(attribute, :invalid_cnpj, message: "não é um CNPJ válido") unless self.class.valid?(value)
  end
end
