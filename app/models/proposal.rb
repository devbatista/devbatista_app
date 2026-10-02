# Proposta comercial (RF 10). Total = soma dos itens. Enviada ou Visualizada vira
# Expirada ao fim da validade, com aviso ao responsável antes (ProposalAlertsJob).
# Aprovada, gera contrato e serviços contratados (ProposalApproval, RF 11).
class Proposal < ApplicationRecord
  include Auditable
  include LabeledEnums

  audited area: "comercial", ignore: %w[total_cents]
  labeled_enum :status, draft: "Rascunho", sent: "Enviada", viewed: "Visualizada", approved: "Aprovada",
                        rejected: "Recusada", expired: "Expirada"

  OPEN_STATUSES = %w[draft sent viewed].freeze

  belongs_to :company, optional: true
  belongs_to :lead, optional: true
  belongs_to :opportunity, optional: true
  belongs_to :contact, optional: true
  belongs_to :user
  belongs_to :contract, optional: true
  has_many :items, -> { order(:position, :id) }, class_name: "ProposalItem", dependent: :destroy, inverse_of: :proposal
  has_many :documents, as: :documentable, dependent: :restrict_with_error

  accepts_nested_attributes_for :items, allow_destroy: true, reject_if: ->(attrs) { attrs["service_id"].blank? }

  validates :title, :valid_until, presence: true
  validate :recipient_present
  validate :contact_from_company
  validates :rejection_reason, presence: { message: "é obrigatório para registrar a recusa" }, if: :rejected?

  before_validation :assign_number, on: :create
  before_validation :suggest_contact
  before_save :compute_total
  before_save :track_status_dates

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :search, lambda { |term|
    text = term.to_s.strip
    clause = "unaccent(proposals.title) ILIKE unaccent(:q)"
    if (m = text.match(/\A#?P?-?(\d{4})-(\d+)\z/i))
      clause += " OR (proposals.year = :year AND proposals.number = :number)"
    end
    where(clause, q: "%#{sanitize_sql_like(text)}%", year: m&.[](1).to_i, number: m&.[](2).to_i)
  }

  def code
    "#P-#{year}-#{format('%03d', number)}" if number
  end

  def recipient
    company || lead
  end

  def recipient_name
    company&.trade_name || lead&.display_name
  end

  def days_to_expire(today = Date.current)
    (valid_until - today).to_i
  end

  def editable?
    draft? || sent? || viewed?
  end

  def mrr_cents
    items.sum(&:mrr_cents)
  end

  def activity_name
    "a proposta #{code} (#{title})"
  end

  def activity_company
    company
  end

  def to_s
    "#{code} — #{title}"
  end

  private

  # Sequencial por ano, com trava para dois cadastros simultâneos não pegarem o mesmo número.
  def assign_number
    return if number

    self.year ||= Date.current.year
    self.class.connection.execute("SELECT pg_advisory_xact_lock(#{self.class.connection.quote(31_337 + year)})")
    self.number = self.class.where(year: year).maximum(:number).to_i + 1
  end

  # O contato principal da empresa é sugerido por padrão (RF 13).
  def suggest_contact
    self.contact ||= company&.primary_contact
  end

  def compute_total
    self.total_cents = items.reject(&:marked_for_destruction?).sum { |item| item.price_cents.to_i }
  end

  def track_status_dates
    return unless will_save_change_to_status?

    self.sent_at ||= Time.current if sent?
    self.viewed_at ||= Time.current if viewed?
    self.decided_on ||= Date.current if approved? || rejected?
  end

  def recipient_present
    errors.add(:base, "Informe o cliente ou o lead destinatário") if company_id.blank? && lead_id.blank?
  end

  def contact_from_company
    errors.add(:contact, "não é da empresa da proposta") if contact && company && contact.company_id != company_id
  end
end
