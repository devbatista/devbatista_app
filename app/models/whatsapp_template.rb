# Template de mensagem aprovado pela Meta, por conta (docs/specs/whatsapp). É o único jeito de
# iniciar uma conversa ou retomar depois de 24h sem resposta. Os componentes ficam no formato da
# Graph API (HEADER, BODY, FOOTER, BUTTONS); o status vem da Meta (webhook e sincronização).
class WhatsappTemplate < ApplicationRecord
  include Auditable
  include LabeledEnums

  LANGUAGES = { "pt_BR" => "Português (BR)", "en_US" => "Inglês (EUA)", "es" => "Espanhol" }.freeze
  VARIABLE = /\{\{\s*(\w+)\s*\}\}/

  audited area: "whatsapp", ignore: %w[last_synced_at], activity: false
  labeled_enum :category, marketing: "Marketing", utility: "Utilidade", authentication: "Autenticação", free_service: "Atendimento"
  labeled_enum :status, {
    approved: "Aprovado", pending: "Em análise", rejected: "Rejeitado", paused: "Pausado", disabled: "Desativado",
    in_appeal: "Em recurso", limit_exceeded: "Limite excedido", archived: "Arquivado", pending_deletion: "Excluindo",
    deleted: "Excluído"
  }, prefix: :status

  belongs_to :account, class_name: "WhatsappAccount", foreign_key: :whatsapp_account_id, inverse_of: :templates

  before_validation { self.variables_count = header_and_body_variables.size }

  validates :name, presence: true, format: { with: /\A[a-z0-9_]{1,512}\z/, message: "usa só letras minúsculas, números e _" }
  validates :name, uniqueness: { scope: %i[whatsapp_account_id language] }
  validates :language, presence: true

  scope :usable, -> { status_approved.order(:name) }

  # Atributos a partir de um template da Graph API, que manda categoria e status em maiúsculas
  # (UTILITY, APPROVED…) e rejected_reason "NONE" quando não há motivo. Valor que os enums não
  # conhecem (a Meta pode criar novos) não para a sincronização: vira um padrão seguro, com aviso
  # no log. O status vira "pending"; a categoria fica a do template atual (current) ou "utility".
  def self.attributes_from_meta(data, current: nil)
    reason = data["rejected_reason"].presence
    {
      meta_template_id: data["id"], name: data["name"], language: data["language"],
      category: known_value(data, "category", CATEGORY_LABELS) { current&.category.presence || "utility" },
      status: known_value(data, "status", STATUS_LABELS) { "pending" },
      components: data["components"] || [], rejection_reason: (reason unless reason == "NONE")
    }.compact
  end

  def self.known_value(data, field, labels)
    value = data[field].to_s.downcase.presence
    return value if value.nil? || labels.key?(value)

    Rails.logger.warn("[Whatsapp] valor desconhecido: #{field}=#{data[field]}, template=#{data["name"]}")
    yield
  end
  private_class_method :known_value

  def component(type)
    Array(components).find { |c| c["type"].to_s.casecmp?(type) }
  end

  def body_text
    component("BODY")&.dig("text").to_s
  end

  def language_label
    LANGUAGES.fetch(language, language)
  end

  def to_s
    "#{name} (#{language})"
  end

  private

  # Variáveis que o envio precisa preencher: as do cabeçalho de texto e as do corpo. Cada
  # componente numera as suas ({{1}}, {{2}}…) ou usa nomes ({{nome}}).
  def header_and_body_variables
    header = component("HEADER")
    texts = { "header" => (header && header["format"].to_s.casecmp?("TEXT") ? header["text"].to_s : ""), "body" => body_text }
    texts.flat_map { |part, text| text.scan(VARIABLE).flatten.uniq.map { |v| "#{part}:#{v}" } }
  end
end
