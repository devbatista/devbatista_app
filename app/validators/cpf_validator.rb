# CPF com dígitos verificadores (módulo 11), como o CnpjValidator.
#
#   validates :cpf, cpf: true
#   CpfValidator.valid?("529.982.247-25")  # => true
class CpfValidator < ActiveModel::EachValidator
  def self.valid?(value)
    digits = value.to_s.gsub(/\D/, "")
    return false unless digits.size == 11 && digits.squeeze.size > 1

    numbers = digits.chars.map(&:to_i)
    check_digit(numbers[0, 9]) == numbers[9] && check_digit(numbers[0, 10]) == numbers[10]
  end

  # Pesos decrescentes a partir de 10 (1º dígito) ou 11 (2º dígito).
  def self.check_digit(numbers)
    rest = numbers.each_with_index.sum { |n, i| n * (numbers.size + 1 - i) } % 11
    rest < 2 ? 0 : 11 - rest
  end

  def self.format(value)
    digits = value.to_s.gsub(/\D/, "")
    return value unless digits.size == 11

    "#{digits[0, 3]}.#{digits[3, 3]}.#{digits[6, 3]}-#{digits[9, 2]}"
  end

  def validate_each(record, attribute, value)
    record.errors.add(attribute, :invalid_cpf, message: "não é um CPF válido") unless self.class.valid?(value)
  end
end
