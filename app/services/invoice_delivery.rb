# Envia a fatura emitida ao cliente por e-mail, com o PDF anexado e o botão "Ver fatura" (link
# público). Guarda o PDF enviado em Documentos (cada envio, a sua versão), marca a data de envio
# e põe o e-mail na fila (Sidekiq). Fatura vencida também pode ser reenviada.
class InvoiceDelivery
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :to, :string
  attribute :cc, :string
  attribute :subject, :string
  attribute :message, :string
  attribute :copy_me, :boolean, default: true

  attr_reader :invoice, :user, :document

  validates :to, :subject, :message, presence: true
  validate :emails_valid
  validate :invoice_can_be_sent

  def initialize(invoice:, user:, **attributes)
    @invoice = invoice
    @user = user
    super(**attributes)
    self.to ||= invoice.recipient_email
    self.subject ||= "Fatura #{invoice.code} — #{Setting[:company_name]}"
    self.message ||= default_message
  end

  def save
    return false unless valid?

    pdf = InvoicePdf.new(invoice, view_url: view_url)
    ActiveRecord::Base.transaction do
      @document = Document.new(documentable: invoice, kind: "invoice", uploaded_by: user,
                               title: "Fatura #{invoice.code} enviada em #{I18n.l(Date.current, format: '%d/%m/%Y')}",
                               notes: "Enviada por e-mail para #{recipients.join(', ')}")
      @document.file.attach(io: StringIO.new(pdf.render), filename: pdf.filename, content_type: "application/pdf")
      @document.save!
      invoice.mark_sent!
    end
    InvoiceMailer.client(invoice: invoice, document: document, sender: user, to: to_list, cc: cc_list, bcc: bcc_list,
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

  def view_url
    Rails.application.routes.url_helpers.invoice_view_url(invoice.generate_token_for(:client_view), **ActionMailer::Base.default_url_options)
  end

  def to_list = split(to)
  def cc_list = split(cc)
  def bcc_list = copy_me && user.email.present? ? [ user.email ] : []

  def split(value)
    value.to_s.split(/[,;\s]+/).map { |email| email.strip.downcase }.compact_blank.uniq
  end

  def default_message
    greeting = invoice.recipient_first_name.present? ? "Olá, #{invoice.recipient_first_name}!" : "Olá!"
    <<~TEXT.strip
      #{greeting}

      Segue a fatura #{invoice.code}, no valor de #{ApplicationController.helpers.brl(invoice.total_cents)}, com vencimento em #{I18n.l(invoice.due_on, format: '%d/%m/%Y')}. O PDF está anexado e a fatura também pode ser aberta pelo botão abaixo, com o Pix para pagamento.

      Qualquer dúvida, é só responder este e-mail.

      #{user.name}
      #{Setting[:company_name]}
    TEXT
  end

  def emails_valid
    errors.add(:to, "precisa ter ao menos um e-mail") if to.present? && to_list.empty?
    errors.add(:base, "Use no máximo 10 destinatários") if recipients.size > 10
    invalid = recipients.grep_v(URI::MailTo::EMAIL_REGEXP)
    errors.add(:base, "E-mail inválido: #{invalid.join(', ')}") if invalid.any?
  end

  def invoice_can_be_sent
    errors.add(:base, "Só fatura emitida pode ser enviada (esta está #{invoice.status_label.downcase})") unless invoice.issued?
  end
end
