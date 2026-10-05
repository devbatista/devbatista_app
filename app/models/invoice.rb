# Nota fiscal emitida fora do sistema (RF 28): número, competência, valor e PDF, XML ou link.
# A emissão automática fica para a V1.1. Uma nota pode cobrir várias receitas do cliente.
class Invoice < ApplicationRecord
  include Auditable
  include LabeledEnums
  include MoneyAttributes

  MAX_FILE_SIZE = 10.megabytes
  FILE_TYPES = %w[application/pdf application/xml text/xml].freeze

  audited area: "financeiro"
  labeled_enum :status, pending: "Pendente de emissão", issued: "Emitida", cancelled: "Cancelada"
  money_attribute :amount

  belongs_to :company
  has_many :receivables, dependent: :nullify
  has_many_attached :files

  validates :competence, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :number, presence: { message: "é obrigatório para nota emitida" }, if: :issued?
  validates :number, uniqueness: { message: "já registrado em outra nota" }, allow_blank: true
  validates :issued_on, presence: { message: "é obrigatória quando a nota é emitida" }, if: :issued?
  validates :url, format: { with: %r{\Ahttps?://[^\s]+\z}i, message: "precisa começar com http:// ou https://" }, allow_blank: true
  validate :files_are_pdf_or_xml
  validate :receivables_from_same_company

  normalizes :number, with: ->(value) { value.to_s.strip.presence }
  before_validation { self.competence = competence&.beginning_of_month }

  scope :search, lambda { |term|
    joins(:company).where("invoices.number ILIKE :q OR unaccent(companies.trade_name) ILIKE unaccent(:q) OR unaccent(invoices.description) ILIKE unaccent(:q)",
                          q: "%#{sanitize_sql_like(term.to_s.strip)}%")
  }

  def competence_month
    competence&.strftime("%Y-%m")
  end

  def competence_month=(value)
    self.competence = value.present? ? Date.strptime(value.to_s, "%Y-%m") : nil
  rescue Date::Error
    self.competence = nil
  end

  def code
    number ? "NF #{number}" : "NF pendente"
  end

  def activity_name
    "a nota fiscal #{number || '(pendente)'} de #{company&.trade_name}"
  end

  def to_s
    code
  end

  private

  def files_are_pdf_or_xml
    files.each do |file|
      errors.add(:files, "#{file.filename}: envie PDF ou XML") unless file.content_type.in?(FILE_TYPES) || file.filename.to_s.match?(/\.(pdf|xml)\z/i)
      errors.add(:files, "#{file.filename} passa do limite de 10 MB") if file.blob.byte_size > MAX_FILE_SIZE
    end
  end

  def receivables_from_same_company
    errors.add(:receivables, "precisam ser do mesmo cliente da nota") if receivables.any? { |r| r.company_id != company_id }
  end
end
