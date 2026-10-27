# Lead: contato com potencial de negócio, antes de virar cliente (RF 6).
# Anda no pipeline até Qualificado; daí em diante quem anda é a oportunidade (RF 7).
class Lead < ApplicationRecord
  include Auditable
  include LabeledEnums
  include Losable

  audited area: "comercial"
  labeled_enum :origin, whatsapp: "WhatsApp", referral: "Indicação", site: "Site", diagnosis: "Diagnóstico",
                        meta_ads: "Meta Ads", google_ads: "Google Ads", linkedin: "LinkedIn", outbound: "Outbound", other: "Outros"
  labeled_enum :status, { new: "Novo Lead", contacted: "Contato Realizado", qualified: "Qualificado",
                          converted: "Convertido", lost: "Perdido" }, prefix: :status

  OPEN_STATUSES = %w[new contacted qualified].freeze

  belongs_to :service, optional: true
  belongs_to :user
  belongs_to :company, optional: true
  has_many :opportunities, dependent: :nullify
  has_many :proposals, dependent: :restrict_with_error
  has_many :interactions, as: :subject, dependent: :destroy
  has_many :whatsapp_conversations, dependent: :nullify

  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :name, :origin, :entered_on, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_validation { self.entered_on ||= Date.current }
  before_save { self.lost_at = (status_lost? ? (lost_at || Time.current) : nil) }

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :search, lambda { |term|
    like = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("unaccent(leads.name) ILIKE unaccent(:q) OR unaccent(leads.company_name) ILIKE unaccent(:q) OR leads.email ILIKE :q", q: like)
  }

  def lost? = status_lost?
  def open? = status.in?(OPEN_STATUSES)

  def display_name
    company_name.presence || name
  end

  def initials
    name.to_s.split.values_at(0, -1).compact.uniq.map { |part| part[0] }.join.upcase
  end

  def activity_name
    "o lead #{display_name}"
  end

  def to_s
    company_name.present? ? "#{company_name} · #{name}" : name
  end

  private

  def status_attribute = :status
end
