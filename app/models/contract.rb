# Contrato com o cliente: vigência, renovação, valor e documento assinado (RF 17).
# O número é sequencial e gerado pelo banco. O status muda sozinho para "Próximo do
# vencimento" pela rotina diária (ContractAlertsJob).
class Contract < ApplicationRecord
  include Auditable
  include LabeledEnums
  include MoneyAttributes

  audited area: "contratos"
  labeled_enum :status, draft: "Rascunho", active: "Ativo", expiring: "Próximo do vencimento", ended: "Encerrado", cancelled: "Cancelado"
  labeled_enum :renewal, { automatic: "Automática", manual: "Manual", none: "Sem renovação" }, prefix: true
  labeled_enum :periodicity, monthly: "Mensal", quarterly: "Trimestral", semiannual: "Semestral", annual: "Anual", one_time: "Valor único"
  money_attribute :value

  belongs_to :company
  has_many :customer_services, dependent: :nullify
  has_many :documents, as: :documentable, dependent: :restrict_with_error

  validates :title, :start_date, :end_date, presence: true
  validates :value_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :end_after_start

  scope :current, -> { where(status: %w[active expiring]) }
  scope :by_end_date, -> { order(:end_date) }
  scope :search, lambda { |term|
    number = term.to_s.delete("#").strip
    like = "%#{sanitize_sql_like(term.to_s.strip)}%"
    clause = "unaccent(contracts.title) ILIKE unaccent(:like)"
    clause += " OR contracts.number = :number" if number.match?(/\A\d+\z/)
    where(clause, like: like, number: number.to_i)
  }

  # Valor mensalizado, para somar com o MRR.
  def monthly_value_cents
    divisor = { "monthly" => 1, "quarterly" => 3, "semiannual" => 6, "annual" => 12 }[periodicity]
    divisor ? (value_cents / divisor.to_f).round : 0
  end

  def days_left(today = Date.current)
    (end_date - today).to_i
  end

  def elapsed_ratio(today = Date.current)
    total = (end_date - start_date).to_f
    return 1.0 if total <= 0

    ((today - start_date) / total).clamp(0, 1)
  end

  def signed_document
    documents.where(kind: "contract").order(:created_at).first
  end

  # "renovação automática", "renovação manual" ou "sem renovação", para frases.
  def renewal_text
    renewal_none? ? "sem renovação" : "renovação #{renewal_label.downcase}"
  end

  def code
    "##{format('%03d', number)}" if number
  end

  def activity_name
    "o contrato #{code}"
  end

  def to_s
    [ code, title ].compact.join(" — ")
  end

  private

  def end_after_start
    errors.add(:end_date, "precisa ser depois do início") if start_date && end_date && end_date <= start_date
  end
end
