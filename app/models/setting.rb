# Configurações editáveis sem deploy (RF 42). Cada chave tem um valor padrão;
# o banco só guarda o que foi alterado.
#
#   Setting[:contract_alert_days]  # => [60, 30, 15]
class Setting < ApplicationRecord
  include Auditable

  audited area: "administracao", activity: false

  DEFAULTS = {
    "company_name" => "DevBatista",
    "company_legal_name" => "DevBatista Tecnologia Ltda.",
    "company_cnpj" => "",
    "company_whatsapp" => "",
    "company_site" => "https://devbatista.com",
    "mailer_sender" => "nao-responda@devbatista.com",
    "email_enabled" => true,
    "daily_run_time" => "07:00",
    "session_timeout_minutes" => 30,
    "contract_alert_days" => [ 60, 30, 15 ],
    "domain_alert_days" => [ 60, 30, 7 ],
    "proposal_alert_days" => 3,
    "loss_reasons" => [ "Preço", "Prazo", "Sem retorno", "Optou por concorrente", "Sem orçamento", "Fora do perfil", "Outro" ],
    "expense_categories" => [ "Infraestrutura", "Software", "Marketing", "Comercial", "Contabilidade", "Impostos", "Colaboradores", "Administrativo", "Outros" ],
    "cost_centers" => [ "Administrativo", "Comercial e marketing", "Operação", "Infraestrutura interna", "Produtos próprios" ],
    "recurrence_months" => 3
  }.freeze

  validates :key, presence: true, uniqueness: true, inclusion: { in: DEFAULTS.keys }
  validate :valid_cnpj, if: -> { key == "company_cnpj" && value.present? }
  validate :valid_whatsapp, if: -> { key == "company_whatsapp" && value.present? }

  def self.[](key)
    key = key.to_s
    Rails.cache.fetch("setting/#{key}") { find_by(key: key)&.value }.then { |value| value.nil? ? DEFAULTS.fetch(key) : value }
  end

  def to_s
    key
  end

  def self.[]=(key, value)
    record = find_or_initialize_by(key: key.to_s)
    record.update!(value: value)
    Rails.cache.delete("setting/#{key}")
  end

  #   Setting.format_phone("11987654321")  # => "(11) 98765-4321"
  def self.format_phone(digits)
    digits.to_s.sub(/\A(\d{2})(\d{4,5})(\d{4})\z/, '(\1) \2-\3')
  end

  private

  def valid_cnpj
    errors.add(:base, "CNPJ da empresa não é válido") unless CnpjValidator.valid?(value)
  end

  # DDD + número, sem o 55: 10 dígitos (fixo) ou 11 (celular).
  def valid_whatsapp
    errors.add(:base, "WhatsApp deve ter DDD e número, como (11) 98765-4321") unless value.to_s.match?(/\A\d{10,11}\z/)
  end
end
