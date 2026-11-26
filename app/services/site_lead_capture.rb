# Lead capturado no site (devbatista.com), no lugar do HubSpot: o Diagnóstico Tecnológico, o e-book e
# o formulário de contato chegam pelo webhook /webhooks/site-leads (Webhooks::SiteLeadsController).
#
# O mesmo e-mail ou o mesmo WhatsApp com lead em aberto completa esse lead em vez de abrir outro: quem
# baixou o e-book e depois fez o diagnóstico continua sendo um lead só, e o contato, que pode vir sem
# e-mail, é achado pelo telefone. Lead perdido ou convertido não é reaberto; o envio novo abre outro
# lead. Só os campos vazios são preenchidos, para não desfazer o que foi editado à mão; o texto
# completo (details) se soma às observações.
#
# Cada envio vira uma interação (nota) com o resumo de uma linha. O diagnóstico e o contato avisam o
# responsável, e o contato ainda deixa o próximo passo de responder pelo WhatsApp.
class SiteLeadCapture
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Tipo de envio do site → origem do lead.
  ORIGINS = { "diagnosis" => "diagnosis", "ebook" => "site", "contact" => "site" }.freeze
  TIERS = %w[frio morno quente].freeze
  # Necessidade marcada no formulário de contato → nome do serviço no catálogo. Fora daqui
  # (agencia, nao_sei ou desconhecida) o lead fica sem serviço de interesse.
  NEED_SERVICES = {
    "whatsapp_ia" => "Inteligência Artificial", "automacao_ia" => "Automação/RPA", "ia_sistemas" => "Inteligência Artificial",
    "sob_medida" => "Desenvolvimento de sistemas", "manutencao" => "Manutenção"
  }.freeze
  CONTACT_NEXT_STEP = "Responder o contato do site pelo WhatsApp".freeze

  attribute :source, :string
  attribute :site_id, :string    # id do envio no JSONL do site
  attribute :name, :string
  attribute :company, :string
  attribute :email, :string
  attribute :phone, :string      # DDD + número, sem o 55
  attribute :summary, :string    # uma linha, para a timeline
  attribute :details, :string    # texto completo, para as observações
  attribute :tier, :string       # potencial comercial do diagnóstico: frio, morno ou quente
  attribute :need, :string       # necessidade do formulário de contato (NEED_SERVICES)
  attribute :consent, :boolean   # aceite do formulário de contato, só registrado nas observações

  attr_reader :lead

  validates :source, inclusion: { in: ORIGINS.keys }
  validates :email, presence: true, unless: :contact?
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :name, presence: true, if: -> { diagnosis? || contact? }
  validates :phone, presence: true, if: :contact?

  # Responsável pelos leads do site: o administrador ativo mais antigo.
  def self.owner
    User.active.joins(:role).where(roles: { key: "admin" }).order(:created_at).first
  end

  def diagnosis? = source == "diagnosis"
  def contact? = source == "contact"
  def created? = @created

  def save
    return false unless valid?

    owner = self.class.owner
    unless owner
      errors.add(:base, "Nenhum administrador ativo para receber o lead")
      return false
    end

    Lead.transaction do
      @lead = open_lead
      @created = @lead.nil?
      @lead ||= Lead.new(origin: ORIGINS.fetch(source), status: "new", user: owner, external_id: site_id)
      fill(@lead)
      @lead.save!
      @lead.interactions.create!(kind: "note", occurred_on: Date.current, notes: interaction_notes, user: @lead.user)
    end
    notify if diagnosis? || contact?
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.merge!(e.record.errors)
    false
  end

  private

  def whatsapp = (Setting.format_phone(phone) if phone.present?)

  # O lead em aberto mais recente com o mesmo e-mail ou o mesmo WhatsApp.
  def open_lead
    matches = [ ({ email: email } if email.present?), ({ whatsapp: whatsapp } if whatsapp) ].compact
    return if matches.empty?

    matches.map { |conditions| Lead.open.where(conditions) }.reduce(:or).order(:created_at).last
  end

  # O e-book chega só com o e-mail, que fica de nome provisório até o diagnóstico trazer o nome.
  def fill(lead)
    lead.email ||= email.presence
    lead.name = name if name.present? && (lead.name.blank? || lead.name == lead.email)
    lead.name = lead.email if lead.name.blank?
    lead.company_name = company if lead.company_name.blank? && company.present?
    lead.whatsapp = whatsapp if lead.whatsapp.blank? && whatsapp
    lead.service ||= need_service
    lead.notes = [ lead.notes, details_with_consent ].compact_blank.join("\n\n") if details_with_consent.present?
    return unless contact? && lead.next_step.blank?

    lead.next_step = CONTACT_NEXT_STEP
    lead.next_step_on = Time.current.change(sec: 0)
  end

  # Serviço do catálogo pela necessidade do contato; se não existir no catálogo, fica sem.
  def need_service
    service_name = NEED_SERVICES[need]
    Service.find_by(name: service_name) if service_name
  end

  def details_with_consent
    consent_line = "Consentimento de contato: #{consent ? 'sim' : 'não'}" unless consent.nil?
    [ details, consent_line ].compact_blank.join("\n").presence
  end

  def interaction_notes
    return summary if summary.present?
    return "Enviou o formulário de contato pelo site" if contact?

    diagnosis? ? "Fez o Diagnóstico Tecnológico pelo site" : "Baixou o e-book pelo site"
  end

  def notify
    Notification.deliver!(kind: "site_lead", title: notification_title, level: notification_level, users: [ lead.user ],
                          notifiable: lead, path: Rails.application.routes.url_helpers.lead_path(lead))
  end

  # Quem manda o formulário de contato está pronto para conversar: sempre "warn".
  def notification_title
    return created? ? "Novo contato do site: #{lead}" : "#{lead} enviou o formulário de contato" if contact?

    title = created? ? "Novo lead do site: #{lead}" : "#{lead} fez o Diagnóstico Tecnológico no site"
    tier.in?(TIERS) ? "#{title} · potencial #{tier}" : title
  end

  def notification_level
    contact? || tier == "quente" ? "warn" : "info"
  end
end
