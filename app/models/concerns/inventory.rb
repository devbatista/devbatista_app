# Inventário de Tecnologia (RF 29 a 34): ambiente, auditoria na área "tecnologia" e a regra de
# que nenhum registro guarda senha, chave ou token, só a referência ao item no cofre de senhas.
module Inventory
  extend ActiveSupport::Concern

  ENVIRONMENTS = { "development" => "Desenvolvimento", "staging" => "Staging", "production" => "Produção" }.freeze
  # Padrões de credencial que não podem ser colados nos campos de texto livre.
  SECRET_PATTERN = /(-----BEGIN [A-Z ]*PRIVATE KEY|\bAKIA[0-9A-Z]{16}\b|\bsk-[A-Za-z0-9_-]{20,}|\b(senha|password|passwd|token|secret)\s*[:=]\s*\S+)/i

  included do
    include Auditable
    include LabeledEnums

    audited area: "tecnologia"
    validate :no_secrets_in_text
  end

  class_methods do
    # Ambiente de desenvolvimento, staging ou produção (servidor, aplicação, banco e integração).
    def environment_field
      labeled_enum :environment, ENVIRONMENTS, prefix: :env
    end
  end

  private

  def no_secrets_in_text
    %w[vault_reference notes description].each do |field|
      next unless has_attribute?(field) && self[field].to_s.match?(SECRET_PATTERN)

      errors.add(field, "parece conter uma senha, chave ou token: registre só a referência ao cofre de senhas")
    end
  end
end
