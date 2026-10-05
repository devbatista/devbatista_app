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
    "company_site" => "https://devbatista.com",
    "mailer_sender" => "nao-responda@devbatista.com",
    "email_enabled" => true,
    "daily_run_time" => "07:00",
    "contract_alert_days" => [ 60, 30, 15 ],
    "domain_alert_days" => [ 60, 30, 7 ],
    "proposal_alert_days" => 3,
    "loss_reasons" => [ "Preço", "Prazo", "Sem retorno", "Optou por concorrente", "Sem orçamento", "Fora do perfil", "Outro" ],
    "expense_categories" => [ "Infraestrutura", "Software", "Marketing", "Comercial", "Contabilidade", "Impostos", "Colaboradores", "Administrativo", "Outros" ],
    "cost_centers" => [ "Administrativo", "Comercial e marketing", "Operação", "Infraestrutura interna", "Produtos próprios" ],
    "recurrence_months" => 3
  }.freeze

  validates :key, presence: true, uniqueness: true, inclusion: { in: DEFAULTS.keys }

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
end
