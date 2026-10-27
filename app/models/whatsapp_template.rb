# Template de mensagem aprovado pela Meta, por conta (docs/specs/whatsapp). É o único jeito de
# iniciar uma conversa ou retomar depois de 24h sem resposta. Os componentes ficam no formato da
# Graph API (HEADER, BODY, FOOTER, BUTTONS); o status vem da Meta (webhook e sincronização).
class WhatsappTemplate < ApplicationRecord
  include Auditable
  include LabeledEnums

  LANGUAGES = { "pt_BR" => "Português (BR)", "en_US" => "Inglês (EUA)", "es" => "Espanhol" }.freeze
  VARIABLE = /\{\{\s*(\w+)\s*\}\}/

  audited area: "whatsapp", ignore: %w[last_synced_at], activity: false
  labeled_enum :category, marketing: "Marketing", utility: "Utilidade", authentication: "Autenticação"
  labeled_enum :status, {
    approved: "Aprovado", pending: "Em análise", rejected: "Rejeitado", paused: "Pausado",
    disabled: "Desativado", in_appeal: "Em recurso", deleted: "Excluído"
  }, prefix: :status

  belongs_to :account, class_name: "WhatsappAccount", foreign_key: :whatsapp_account_id, inverse_of: :templates

  before_validation { self.variables_count = header_and_body_variables.size }

  validates :name, presence: true, format: { with: /\A[a-z0-9_]{1,512}\z/, message: "usa só letras minúsculas, números e _" }
  validates :name, uniqueness: { scope: %i[whatsapp_account_id language] }
  validates :language, presence: true

  scope :usable, -> { status_approved.order(:name) }

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
