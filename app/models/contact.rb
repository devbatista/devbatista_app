# Pessoa de uma empresa. Só um contato principal por empresa; marcar outro
# desmarca o anterior (RF 13).
class Contact < ApplicationRecord
  include Auditable
  include WhatsappLinkable

  audited area: "clientes"

  belongs_to :company, inverse_of: :contacts

  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_save :unset_previous_primary, if: -> { primary? && (new_record? || will_save_change_to_primary? || will_save_change_to_company_id?) }

  scope :by_name, -> { order(:name) }
  scope :primaries, -> { where(primary: true) }
  scope :search, lambda { |term|
    like = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("unaccent(contacts.name) ILIKE unaccent(:like) OR contacts.email ILIKE :like", like: like)
  }

  def initials
    name.to_s.split.values_at(0, -1).compact.uniq.map { |part| part[0] }.join.upcase
  end

  def activity_name
    "o contato #{name}"
  end

  def to_s
    name
  end

  private

  def unset_previous_primary
    Contact.where(company_id: company_id, primary: true).where.not(id: id).find_each { |other| other.update!(primary: false) }
  end
end
