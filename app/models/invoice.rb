# Fatura ao cliente (docs/specs/faturas): agrupa receitas em aberto do mesmo cliente num único
# valor a pagar, com Pix e dados bancários. Rascunho → Emitida (número FAT-AAAA-NNNN, conteúdo
# travado) → Paga ou Cancelada. "Vencida" não é gravada: é a emitida com o vencimento passado.
#
# Os itens guardam uma cópia de cada receita; receivables.invoice_id aponta a fatura ativa da
# receita e volta a nulo quando a fatura é cancelada.
class Invoice < ApplicationRecord
  include Auditable
  include LabeledEnums

  audited area: "financeiro", ignore: %w[total_cents sent_at viewed_at]
  labeled_enum :status, draft: "Rascunho", issued: "Emitida", paid: "Paga", cancelled: "Cancelada"

  ACTIVE_STATUSES = %w[draft issued paid].freeze
  OVERDUE_LABEL = "Vencida".freeze

  belongs_to :company
  belongs_to :contact, optional: true
  has_many :items, -> { order(:position, :created_at) }, class_name: "InvoiceItem", dependent: :destroy, inverse_of: :invoice
  has_many :receivables, dependent: :nullify
  has_many :documents, as: :documentable, dependent: :restrict_with_error

  # Link público (/f/<token>): sem prazo; quem tem o link vê a fatura e baixa o PDF.
  generates_token_for :client_view

  validates :due_on, presence: true
  validate :contact_from_company
  validate :has_items, unless: :cancelled?
  validates :cancellation_reason, presence: { message: "é obrigatório para cancelar" }, if: :cancelled?
  validates :paid_on, presence: { message: "precisa ser informada" }, if: :paid?

  before_validation :suggest_contact
  before_save :compute_total

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :overdue, ->(today = Date.current) { issued.where(due_on: ...today) }
  scope :awaiting_payment, ->(today = Date.current) { issued.where(due_on: today..) }
  scope :search, lambda { |term|
    text = term.to_s.strip
    clause = "unaccent(companies.trade_name) ILIKE unaccent(:q)"
    if (m = text.match(/\A(?:FAT-?)?(\d{4})-?(\d+)\z/i))
      clause += " OR (invoices.year = :year AND invoices.number = :number)"
    end
    joins(:company).where(clause, q: "%#{sanitize_sql_like(text)}%", year: m&.[](1).to_i, number: m&.[](2).to_i)
  }

  # Receitas que podem entrar numa fatura deste cliente: em aberto e sem outra fatura ativa.
  def self.billable_receivables(company_id, invoice: nil)
    Receivable.open.where(company_id: company_id).where(invoice_id: [ nil, invoice&.id ].uniq)
  end

  def code
    number ? "FAT-#{year}-#{format('%04d', number)}" : "Rascunho"
  end

  # Identificador da transação no Pix (só letras e números, até 25).
  def txid
    code.delete("-")
  end

  def overdue?(today = Date.current)
    issued? && due_on < today
  end

  def open? = issued?

  def editable? = draft?

  def display_status_key(today = Date.current)
    overdue?(today) ? "overdue" : status
  end

  def display_status_label(today = Date.current)
    overdue?(today) ? OVERDUE_LABEL : status_label
  end

  def days_late(today = Date.current)
    overdue?(today) ? (today - due_on).to_i : 0
  end

  # Receitas escolhidas no formulário: monta os itens com a cópia de cada uma (só no rascunho).
  def receivable_ids_for_items=(ids)
    chosen = Invoice.billable_receivables(company_id, invoice: persisted? ? self : nil).where(id: Array(ids).compact_blank).by_due.to_a
    @chosen_receivables = chosen
    items.each { |item| item.mark_for_destruction unless chosen.any? { |r| r.id == item.receivable_id } }
    chosen.each_with_index do |receivable, index|
      item = items.find { |i| i.receivable_id == receivable.id } || items.build(receivable: receivable)
      item.assign_attributes(description: receivable.description, competence: receivable.competence,
                             amount_cents: receivable.amount_cents, position: index)
    end
  end

  def receivable_ids_for_items
    items.reject(&:marked_for_destruction?).map(&:receivable_id)
  end

  # Rascunho → Emitida: número do ano, data de emissão, e as receitas passam a apontar para a
  # fatura, com o vencimento dela.
  def issue!(today = Date.current)
    raise ActiveRecord::RecordInvalid, self unless draft?

    transaction do
      lock!
      items.each { |item| ensure_billable!(item.receivable) }
      assign_number(today.year)
      update!(status: "issued", issued_on: today)
      items.each { |item| item.receivable.move_to_invoice!(self, today) }
    end
  end

  # Pagamento integral: a fatura e cada receita dela ficam pagas na mesma data.
  def register_payment!(paid_on:, notes: nil)
    transaction do
      update!(status: "paid", paid_on: paid_on, notes: [ self.notes, notes ].compact_blank.join("\n").presence)
      items.includes(:receivable).find_each do |item|
        next if item.receivable.paid?

        item.receivable.register_payment!(paid_on: paid_on, amount: item.amount_cents / 100.0, notes: "Pago pela fatura #{code}")
      end
    end
  end

  # As receitas voltam a ficar sem fatura e podem entrar em outra.
  def cancel!(reason)
    transaction do
      update!(status: "cancelled", cancellation_reason: reason.to_s.strip.presence)
      receivables.update_all(invoice_id: nil, updated_at: Time.current)
    end
  end

  def mark_sent!
    update_columns(sent_at: Time.current, updated_at: Time.current)
  end

  def mark_viewed!
    update_columns(viewed_at: Time.current) unless viewed_at
  end

  # Último PDF enviado por e-mail (InvoiceDelivery), guardado em Documentos.
  def sent_document
    documents.where(kind: "invoice").order(created_at: :desc, id: :desc).first
  end

  def recipient_email
    contact&.email.presence || company.email.presence
  end

  def recipient_first_name
    contact&.name.to_s.split.first
  end

  def activity_name
    "a fatura #{code} de #{company&.trade_name}"
  end

  def to_s
    code
  end

  private

  # Sequencial por ano, com trava para duas emissões simultâneas não pegarem o mesmo número.
  def assign_number(year)
    self.class.connection.execute("SELECT pg_advisory_xact_lock(#{self.class.connection.quote(71_337 + year)})")
    self.year = year
    self.number = self.class.where(year: year).maximum(:number).to_i + 1
  end

  def ensure_billable!(receivable)
    receivable.reload
    other = receivable.invoice_id && receivable.invoice_id != id
    return if receivable.open? && receivable.company_id == company_id && !other

    errors.add(:base, "A receita “#{receivable.description}” não pode mais ser faturada (#{other ? 'já está em outra fatura' : receivable.status_label.downcase})")
    raise ActiveRecord::RecordInvalid, self
  end

  def suggest_contact
    self.contact ||= company&.primary_contact
  end

  def compute_total
    self.total_cents = items.reject(&:marked_for_destruction?).sum { |item| item.amount_cents.to_i }
  end

  def has_items
    errors.add(:base, "Escolha ao menos uma receita para a fatura") if items.reject(&:marked_for_destruction?).empty?
  end

  def contact_from_company
    errors.add(:contact, "não é do cliente da fatura") if contact && contact.company_id != company_id
  end
end
