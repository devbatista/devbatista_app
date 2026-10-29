# Lead capturado no site (devbatista.com), no lugar do HubSpot: o Diagnóstico Tecnológico e o e-book
# chegam pelo webhook /webhooks/site-leads (Webhooks::SiteLeadsController).
#
# O mesmo e-mail com lead em aberto completa esse lead em vez de abrir outro: quem baixou o e-book e
# depois fez o diagnóstico continua sendo um lead só. Lead perdido ou convertido não é reaberto; o
# envio novo abre outro lead. Só os campos vazios são preenchidos, para não desfazer o que foi
# editado à mão; o diagnóstico completo (details) se soma às observações.
#
# Cada envio vira uma interação (nota) com o resumo de uma linha, e o diagnóstico avisa o responsável.
class SiteLeadCapture
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Tipo de envio do site → origem do lead.
  ORIGINS = { "diagnosis" => "diagnosis", "ebook" => "site" }.freeze
  TIERS = %w[frio morno quente].freeze

  attribute :source, :string
  attribute :site_id, :string    # id do envio no JSONL do site
  attribute :name, :string
  attribute :company, :string
  attribute :email, :string
  attribute :phone, :string      # DDD + número, sem o 55
  attribute :summary, :string    # uma linha, para a timeline
  attribute :details, :string    # texto completo, para as observações
  attribute :tier, :string       # potencial comercial do diagnóstico: frio, morno ou quente

  attr_reader :lead

  validates :source, inclusion: { in: ORIGINS.keys }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, if: :diagnosis?

  # Responsável pelos leads do site: o administrador ativo mais antigo.
  def self.owner
    User.active.joins(:role).where(roles: { key: "admin" }).order(:created_at).first
  end

  def diagnosis? = source == "diagnosis"
  def created? = @created

  def save
    return false unless valid?

    owner = self.class.owner
    unless owner
      errors.add(:base, "Nenhum administrador ativo para receber o lead")
      return false
    end

    Lead.transaction do
      @lead = Lead.open.where(email: email).order(:created_at).last
      @created = @lead.nil?
      @lead ||= Lead.new(origin: ORIGINS.fetch(source), status: "new", user: owner, external_id: site_id)
      fill(@lead)
      @lead.save!
      @lead.interactions.create!(kind: "note", occurred_on: Date.current, notes: interaction_notes, user: @lead.user)
    end
    notify if diagnosis?
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.merge!(e.record.errors)
    false
  end

  private

  # O e-book chega só com o e-mail, que fica de nome provisório até o diagnóstico trazer o nome.
  def fill(lead)
    lead.email ||= email
    lead.name = name if name.present? && (lead.name.blank? || lead.name == lead.email)
    lead.name = lead.email if lead.name.blank?
    lead.company_name = company if lead.company_name.blank? && company.present?
    lead.whatsapp = Setting.format_phone(phone) if lead.whatsapp.blank? && phone.present?
    lead.notes = [ lead.notes, details ].compact_blank.join("\n\n") if details.present?
  end

  def interaction_notes
    summary.presence || (diagnosis? ? "Fez o Diagnóstico Tecnológico pelo site" : "Baixou o e-book pelo site")
  end

  def notify
    title = created? ? "Novo lead do site: #{lead}" : "#{lead} fez o Diagnóstico Tecnológico no site"
    title += " · potencial #{tier}" if tier.in?(TIERS)
    Notification.deliver!(kind: "site_lead", title: title, level: tier == "quente" ? "warn" : "info", users: [ lead.user ],
                          notifiable: lead, path: Rails.application.routes.url_helpers.lead_path(lead))
  end
end
