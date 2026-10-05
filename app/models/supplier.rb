# Fornecedor (RF 36): quem a DevBatista paga, com as mesmas categorias das despesas.
class Supplier < ApplicationRecord
  include Auditable

  audited area: "fornecedores"

  has_many :payables, dependent: :restrict_with_error
  has_many :recurring_expenses, dependent: :restrict_with_error
  has_many :documents, as: :documentable, dependent: :restrict_with_error

  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :name, presence: true, uniqueness: { message: "já cadastrado" }
  validates :category, presence: true
  validates :category, inclusion: { in: ->(_) { Setting[:expense_categories] }, message: "não está na lista de categorias" },
                       if: :will_save_change_to_category?
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :active, -> { where(active: true) }
  scope :by_name, -> { order(:name) }
  scope :search, lambda { |term|
    like = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("unaccent(suppliers.name) ILIKE unaccent(:q) OR unaccent(suppliers.contact_name) ILIKE unaccent(:q) OR suppliers.email ILIKE :q", q: like)
  }

  def website_url
    website.to_s.start_with?("http") ? website : "https://#{website}" if website.present?
  end

  def activity_name
    "o fornecedor #{name}"
  end

  def to_s
    name
  end
end
