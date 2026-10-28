# Template de mensagem aprovado pela Meta, por conta (docs/specs/whatsapp). É o único jeito de
# iniciar uma conversa ou retomar depois de 24h sem resposta. Os componentes ficam no formato da
# Graph API (HEADER, BODY, FOOTER, BUTTONS); o status vem da Meta (webhook e sincronização).
class WhatsappTemplate < ApplicationRecord
  include Auditable
  include LabeledEnums

  LANGUAGES = { "pt_BR" => "Português (BR)", "en_US" => "Inglês (EUA)", "es" => "Espanhol" }.freeze
  VARIABLE = /\{\{\s*(\w+)\s*\}\}/
  # Motivos de rejeição da Meta (rejected_reason na Graph API, reason no webhook).
  REJECTION_REASONS = {
    "INCORRECT_CATEGORY" => "categoria incorreta para o conteúdo",
    "TAG_CONTENT_MISMATCH" => "o conteúdo não combina com a categoria escolhida",
    "INVALID_FORMAT" => "formato inválido (variáveis, exemplos ou caracteres não aceitos)",
    "ABUSIVE_CONTENT" => "conteúdo abusivo ou contra as políticas da Meta",
    "SCAM" => "suspeita de golpe",
    "PROMOTIONAL" => "conteúdo promocional fora da categoria Marketing"
  }.freeze
  # Só estes status podem ser editados na Meta (POST /<TEMPLATE_ID>).
  EDITABLE_STATUSES = %w[approved rejected paused].freeze
  # Categorias que o Admin cria; autenticação vinda da Meta fica só para leitura.
  CREATABLE_CATEGORIES = %w[marketing utility].freeze
  STATUS_NOTES = {
    "paused" => "Pausado pela Meta por avaliação negativa dos destinatários. A 1ª pausa dura 3 h, a 2ª 6 h; na 3ª o template é desativado.",
    "disabled" => "Desativado pela Meta depois de pausas seguidas por qualidade baixa.",
    "limit_exceeded" => "A conta passou do limite de templates da Meta.",
    "in_appeal" => "Em recurso na Meta.",
    "archived" => "Arquivado na Meta.",
    "pending_deletion" => "Sendo excluído na Meta.",
    "deleted" => "Excluído (ou não existe mais na Meta)."
  }.freeze

  audited area: "whatsapp", ignore: %w[last_synced_at components], activity: false
  labeled_enum :category, marketing: "Marketing", utility: "Utilidade", authentication: "Autenticação", free_service: "Atendimento"
  labeled_enum :status, {
    approved: "Aprovado", pending: "Em análise", rejected: "Rejeitado", paused: "Pausado", disabled: "Desativado",
    in_appeal: "Em recurso", limit_exceeded: "Limite excedido", archived: "Arquivado", pending_deletion: "Excluindo",
    deleted: "Excluído"
  }, prefix: :status

  belongs_to :account, class_name: "WhatsappAccount", foreign_key: :whatsapp_account_id, inverse_of: :templates

  before_validation { self.variables_count = header_and_body_variables.size }
  before_save :warn_unknown_rejection, if: :rejection_reason_changed?

  validates :name, presence: true, format: { with: /\A[a-z0-9_]{1,512}\z/, message: "usa só letras minúsculas, números e _" }
  validates :name, uniqueness: { scope: %i[whatsapp_account_id language], conditions: -> { where.not(status: "deleted") } }
  validates :language, presence: true

  scope :usable, -> { status_approved.order(:name) }
  scope :current, -> { where.not(status: "deleted") }
  # Nome ou texto do corpo.
  scope :search, lambda { |term|
    q = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("unaccent(whatsapp_templates.name) ILIKE unaccent(:q) OR EXISTS (SELECT 1 FROM jsonb_array_elements(whatsapp_templates.components) c " \
          "WHERE c->>'type' = 'BODY' AND unaccent(c->>'text') ILIKE unaccent(:q))", q: q)
  }

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

  # O webhook grava "CÓDIGO — detalhe"; a sincronização, só o código.
  def rejection_code
    rejection_reason.to_s.split(" — ", 2).first.presence
  end

  # Motivo em português, com o código da Meta. Código desconhecido aparece cru.
  def rejection_label
    return if rejection_reason.blank?

    code, detail = rejection_reason.split(" — ", 2)
    text = REJECTION_REASONS.key?(code) ? "#{REJECTION_REASONS[code]} (#{code})" : code
    [ text, detail ].compact_blank.join(". ")
  end

  def status_note
    STATUS_NOTES[status]
  end

  def read_only?
    authentication? || free_service? || status_deleted?
  end

  def editable?
    !read_only? && meta_template_id.present? && EDITABLE_STATUSES.include?(status)
  end

  def deletable?
    !status_deleted? && !status_pending_deletion?
  end

  # Envio ainda em andamento com este template (mensagem "Enviando"): a exclusão espera.
  def pending_sends?
    WhatsappMessage.joins(:conversation).where(whatsapp_conversations: { whatsapp_account_id: whatsapp_account_id })
                   .where(kind: "template", status: "pending", template_name: name, template_language: language).exists?
  end

  def to_s
    "#{name} (#{language})"
  end

  private

  def warn_unknown_rejection
    code = rejection_code
    Rails.logger.warn("[Whatsapp] motivo de rejeição desconhecido: #{code}, template=#{name}") if code && !REJECTION_REASONS.key?(code)
  end

  # Variáveis que o envio precisa preencher: as do cabeçalho de texto e as do corpo. Cada
  # componente numera as suas ({{1}}, {{2}}…) ou usa nomes ({{nome}}).
  def header_and_body_variables
    header = component("HEADER")
    texts = { "header" => (header && header["format"].to_s.casecmp?("TEXT") ? header["text"].to_s : ""), "body" => body_text }
    texts.flat_map { |part, text| text.scan(VARIABLE).flatten.uniq.map { |v| "#{part}:#{v}" } }
  end
end
