# Receita e título a receber num registro só (RF 23 e 25): Receitas lista por competência,
# Contas a receber por vencimento. Os recorrentes nascem dos serviços contratados ativos pela
# rotina de recorrências (RecurrenceRoutine), uma única vez por competência.
class Receivable < ApplicationRecord
  include FinancialTitle

  OTHER_CATEGORY = "Outros".freeze

  audited area: "financeiro"
  money_attribute :paid_amount

  belongs_to :company
  belongs_to :contact, optional: true
  belongs_to :customer_service, optional: true
  belongs_to :service, optional: true
  belongs_to :contract, optional: true
  belongs_to :invoice, optional: true

  validate :links_from_same_company

  before_validation :fill_from_customer_service
  before_validation :suggest_contact
  before_validation { self.category = service&.name if category.blank? }

  scope :search, lambda { |term|
    joins(:company).where("unaccent(receivables.description) ILIKE unaccent(:q) OR unaccent(companies.trade_name) ILIKE unaccent(:q)",
                          q: "%#{sanitize_sql_like(term.to_s.strip)}%")
  }

  # Totais por situação (RF 22). Os status partem as receitas válidas, então
  # Faturamento = Recebido + A receber + Vencido; canceladas ficam fora.
  def self.summary(relation = all)
    sums = relation.group(:status).sum(:amount_cents)
    counts = relation.group(:status).count
    {
      billed: sums.except("cancelled").values.sum, billed_count: counts.except("cancelled").values.sum,
      paid: sums["paid"].to_i, paid_count: counts["paid"].to_i,
      open: sums["forecast"].to_i + sums["pending"].to_i, open_count: counts["forecast"].to_i + counts["pending"].to_i,
      overdue: sums["overdue"].to_i, overdue_count: counts["overdue"].to_i
    }
  end

  # Categorias: os serviços do catálogo (a categoria é sugerida pelo serviço) e "Outros".
  def self.categories
    (Service.by_name.pluck(:name) + [ OTHER_CATEGORY ]).uniq
  end

  def recurring?
    customer_service_id.present?
  end

  def origin_label
    if recurring? then "recorrente"
    elsif service&.one_off? then "avulso"
    elsif service&.project? then "projeto"
    end
  end

  # Pagamento informado na tela "Registrar pagamento".
  def register_payment!(paid_on:, amount: nil, notes: nil)
    update!(paid_on: paid_on, paid_amount: amount.presence || self.amount, notes: [ self.notes, notes ].compact_blank.join("\n").presence)
  end

  def activity_name
    "a receita #{description} de #{company&.trade_name}"
  end

  def to_s
    description
  end

  private

  def fill_from_customer_service
    return unless customer_service

    self.company ||= customer_service.company
    self.service ||= customer_service.service
    self.contract ||= customer_service.contract
  end

  # O contato principal da empresa é sugerido por padrão nas cobranças (RF 13).
  def suggest_contact
    self.contact ||= company&.primary_contact
  end

  def links_from_same_company
    errors.add(:contract, "é de outra empresa") if contract && contract.company_id != company_id
    errors.add(:contact, "não é da empresa") if contact && contact.company_id != company_id
    errors.add(:customer_service, "é de outra empresa") if customer_service && customer_service.company_id != company_id
    errors.add(:invoice, "é de outra empresa") if invoice && invoice.company_id != company_id
  end
end
