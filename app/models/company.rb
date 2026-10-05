# Empresa: o centro do sistema. Quase todo registro operacional, financeiro e
# tecnológico pertence a uma empresa (RF 12).
class Company < ApplicationRecord
  include Auditable
  include LabeledEnums

  audited area: "clientes"
  labeled_enum :status, prospect: "Prospect", active: "Ativo", inactive: "Inativo"

  has_many :contacts, -> { order(primary: :desc, name: :asc) }, dependent: :destroy, inverse_of: :company
  has_one :primary_contact, -> { where(primary: true) }, class_name: "Contact", inverse_of: :company
  has_many :contracts, dependent: :restrict_with_error
  has_many :customer_services, dependent: :restrict_with_error
  has_many :documents, dependent: :restrict_with_error
  has_many :activities, dependent: nil
  has_many :opportunities, dependent: :restrict_with_error
  has_many :proposals, dependent: :restrict_with_error
  has_many :leads, dependent: :nullify
  has_many :projects, dependent: :restrict_with_error
  has_many :tickets, dependent: :restrict_with_error
  has_many :time_entries, dependent: :restrict_with_error
  has_many :receivables, dependent: :restrict_with_error
  has_many :invoices, dependent: :restrict_with_error
  has_many :payables, dependent: :restrict_with_error

  normalizes :cnpj, with: ->(value) { value.to_s.gsub(/\D/, "") }
  normalizes :state, with: ->(value) { value.to_s.strip.upcase.presence }
  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :legal_name, :trade_name, presence: true
  validates :cnpj, presence: true, cnpj: true, uniqueness: { message: "já cadastrado em outra empresa" }
  validates :state, length: { is: 2 }, allow_blank: true

  before_save :set_customer_since

  scope :by_name, -> { order(:trade_name) }
  scope :search, lambda { |term|
    digits = term.to_s.gsub(/\D/, "")
    like = "%#{sanitize_sql_like(term.to_s.strip)}%"
    clause = "unaccent(trade_name) ILIKE unaccent(:like) OR unaccent(legal_name) ILIKE unaccent(:like)"
    clause += " OR cnpj LIKE :digits" if digits.size >= 3
    where(clause, like: like, digits: "%#{digits}%")
  }

  def formatted_cnpj
    CnpjValidator.format(cnpj)
  end

  # MRR = soma do MRR dos serviços contratados ativos (avulsos não entram).
  def mrr_cents
    customer_services.active.sum(:mrr_cents)
  end

  # Próxima cobrança: o título a receber em aberto que vence primeiro (a partir de hoje) e a soma
  # do que vence na mesma data. Sem títulos, estima pelos serviços contratados ativos.
  def next_charge(today = Date.current)
    titles = receivables.where(status: %w[forecast pending]).where(due_on: today..)
    if (date = titles.minimum(:due_on))
      same_day = titles.where(due_on: date)
      return { date: date, cents: same_day.sum(:amount_cents), count: same_day.count }
    end

    dues = customer_services.active.recurring.filter_map { |cs| [ cs.next_due_date(today), cs.price_cents ] if cs.next_due_date(today) }
    return nil if dues.empty?

    date = dues.map(&:first).min
    { date: date, cents: dues.select { |d, _| d == date }.sum(&:last), count: nil }
  end

  # Custo direto do cliente: despesas com centro de custo nele (RF 24). Servidores, domínios e
  # serviços externos pagos pela DevBatista entram com o módulo Tecnologia.
  def direct_cost_cents(range)
    payables.not_cancelled.where(competence: range.first.beginning_of_month..range.last).sum(:amount_cents)
  end

  # Iniciais do avatar, como no design: "Empresa ACME" → AC, "Cliente A" → CA, "Grupo Norte Logística" → GL.
  def initials
    words = trade_name.to_s.sub(/\AEmpresa\s+/i, "").split
    letters = words.size == 1 ? words.first[0, 2] : words.values_at(0, -1).map { |w| w[0] }.join
    letters.upcase
  end

  def address_line
    [ street, [ city, state ].compact_blank.join("/"), zip_code ].compact_blank.join(" · ")
  end

  def activity_name
    "a empresa #{trade_name}"
  end

  def to_s
    trade_name
  end

  private

  # "Cliente desde" é a data em que a empresa virou cliente ativo pela primeira vez.
  def set_customer_since
    self.customer_since ||= Date.current if active?
  end
end
