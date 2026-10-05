# Banco de dados de uma aplicação (RF 32). Política de backup em branco = sem backup.
class Database < ApplicationRecord
  include Inventory

  TECHNOLOGIES = %w[PostgreSQL MySQL MongoDB Redis SQL\ Server].freeze

  environment_field
  belongs_to :app
  has_one :company, through: :app

  validates :technology, presence: true

  scope :search, lambda { |term|
    joins(app: :company).where("unaccent(apps.name) ILIKE unaccent(:q) OR unaccent(companies.trade_name) ILIKE unaccent(:q) OR databases.provider ILIKE :q",
                               q: "%#{sanitize_sql_like(term.to_s.strip)}%")
  }

  def backup? = backup_policy.present?

  def activity_name
    "o banco #{technology} de #{app&.name}"
  end

  def activity_company
    app&.company
  end

  def to_s
    [ technology, version ].compact_blank.join(" ")
  end
end
