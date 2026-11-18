# Chave Pix (DICT do Banco Central): o tipo, o formato que vai no BR Code e a validação.
#
# Formatos aceitos pelo banco, e guardados assim nas Configurações:
# - CNPJ e CPF: só os dígitos, com os verificadores conferidos;
# - celular: +55, DDD e número (+5511987654321);
# - e-mail: em minúsculas, até 77 caracteres;
# - aleatória (EVP): UUID em minúsculas.
#
#   PixKey.normalize("phone", "(11) 98765-4321")  # => "+5511987654321"
#   PixKey.error("61408507000163")                # => "CNPJ inválido: confira os dígitos"
#   PixKey.format("61408507000173")               # => "61.408.507/0001-73"
class PixKey
  TYPES = { "cnpj" => "CNPJ", "cpf" => "CPF", "phone" => "Celular", "email" => "E-mail", "random" => "Chave aleatória" }.freeze
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  PHONE = /\A\+55\d{10,11}\z/

  # Tipo de uma chave já guardada (ou digitada sem tipo): pelo formato.
  def self.detect(value)
    text = value.to_s.strip
    return if text.empty?
    return "email" if text.include?("@")
    return "random" if text.match?(UUID)
    return "phone" if text.start_with?("+") || text.include?("(")

    digits = text.gsub(/\D/, "")
    { 14 => "cnpj", 11 => "cpf" }[digits.size]
  end

  # Formato do BR Code. Sem tipo, deduz pelo formato do que foi digitado.
  def self.normalize(type, value)
    text = value.to_s.strip
    return "" if text.empty?

    case type.presence || detect(text)
    when "cnpj", "cpf" then text.gsub(/\D/, "")
    when "phone"
      digits = text.gsub(/\D/, "")
      digits = "55#{digits}" if digits.size.in?([ 10, 11 ])
      "+#{digits}"
    when "email", "random" then text.downcase
    else text
    end
  end

  # Motivo da recusa, em português, ou nil para chave válida.
  def self.error(value)
    text = value.to_s
    case detect(text)
    when "cnpj" then "CNPJ inválido: confira os dígitos" unless CnpjValidator.valid?(text)
    when "cpf" then "CPF inválido: confira os dígitos" unless CpfValidator.valid?(text)
    when "phone" then "celular precisa ter DDD e número, como (11) 98765-4321" unless text.match?(PHONE)
    when "email" then "e-mail inválido" unless text.match?(EMAIL) && text.length <= 77
    when "random" then nil
    else "formato não reconhecido. Use CNPJ, CPF, celular, e-mail ou chave aleatória"
    end
  end

  def self.valid?(value) = error(value).nil?

  # Para mostrar: CNPJ e CPF pontuados, celular como +55 (11) 98765-4321.
  def self.format(value)
    case detect(value)
    when "cnpj" then CnpjValidator.format(value)
    when "cpf" then CpfValidator.format(value)
    when "phone"
      digits = value.to_s.gsub(/\D/, "").delete_prefix("55")
      "+55 #{Setting.format_phone(digits)}"
    else value.to_s
    end
  end
end
