# Envia a proposta ao cliente por e-mail, com o PDF anexado (RF 10).
# Guarda o PDF enviado em Documentos (cada envio, a sua versão), passa Rascunho a Enviada,
# registra a interação no lead ou na oportunidade e põe o e-mail na fila (Sidekiq).
class ProposalDelivery
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :to, :string
  attribute :cc, :string
  attribute :subject, :string
  attribute :message, :string
  attribute :copy_me, :boolean, default: true

  attr_reader :proposal, :user, :document

  validates :to, :subject, :message, presence: true
  validate :emails_valid
  validate :proposal_can_be_sent

  def initialize(proposal:, user:, **attributes)
    @proposal = proposal
    @user = user
    super(**attributes)
    self.to ||= proposal.recipient_email
    self.subject ||= "Proposta #{proposal.code} — #{proposal.title}"
    self.message ||= default_message
  end

  def save
    return false unless valid?

    pdf = ProposalPdf.new(proposal)
    ActiveRecord::Base.transaction do
      @document = Document.new(documentable: proposal, kind: "proposal", uploaded_by: user,
                               title: "Proposta #{proposal.code} enviada em #{I18n.l(Date.current, format: '%d/%m/%Y')}",
                               notes: "Enviada por e-mail para #{recipients.join(', ')}")
      @document.file.attach(io: StringIO.new(pdf.render), filename: pdf.filename, content_type: "application/pdf")
      @document.save!
      if proposal.draft?
        proposal.update!(status: "sent")
        proposal.opportunity&.update!(stage: "proposal") if proposal.opportunity&.stage_meeting?
      end
      log_interaction
    end
    ProposalMailer.client(proposal: proposal, document: document, sender: user, to: to_list, cc: cc_list, bcc: bcc_list,
                           subject: subject, message: message).deliver_later
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence)
    false
  end

  def recipients
    to_list + cc_list
  end

  private

  def to_list = split(to)
  def cc_list = split(cc)
  def bcc_list = copy_me && user.email.present? ? [ user.email ] : []

  def split(value)
    value.to_s.split(/[,;\s]+/).map { |email| email.strip.downcase }.compact_blank.uniq
  end

  def default_message
    greeting = proposal.recipient_first_name.present? ? "Olá, #{proposal.recipient_first_name}!" : "Olá!"
    <<~TEXT.strip
      #{greeting}

      Segue a proposta #{proposal.code} — #{proposal.title}, válida até #{I18n.l(proposal.valid_until, format: '%d/%m/%Y')}. O PDF está anexado e também pode ser aberto pelo botão abaixo.

      Qualquer dúvida, é só responder este e-mail.

      #{user.name}
      #{Setting[:company_name]}
    TEXT
  end

  # Fica no histórico comercial: na oportunidade, se houver; senão, no lead.
  def log_interaction
    subject_record = proposal.opportunity || proposal.lead
    return unless subject_record

    Interaction.create!(subject: subject_record, user: user, kind: "email", occurred_on: Date.current,
                        notes: "Proposta #{proposal.code} enviada por e-mail para #{recipients.join(', ')}.")
  end

  def emails_valid
    errors.add(:to, "precisa ter ao menos um e-mail") if to.present? && to_list.empty?
    errors.add(:base, "Use no máximo 10 destinatários") if recipients.size > 10
    invalid = recipients.grep_v(URI::MailTo::EMAIL_REGEXP)
    errors.add(:base, "E-mail inválido: #{invalid.join(', ')}") if invalid.any?
  end

  def proposal_can_be_sent
    errors.add(:base, "Proposta #{proposal.status_label.downcase} não pode ser enviada") unless proposal.editable?
    errors.add(:base, "Inclua ao menos um serviço antes de enviar") if proposal.items.empty?
  end
end
