# Comportamento comum de Receivable (receita / título a receber) e Payable (despesa / conta a
# pagar): mesmos status, competência mensal, pagamento e atraso (RF 23 a 26).
#
# - Previsto: gerado pela rotina de recorrências para um mês futuro;
# - Pendente: do mês corrente ou lançado à mão, aguardando pagamento;
# - Vencido: no dia seguinte ao vencimento sem pagamento (rotina diária);
# - Pago: com data de pagamento;
# - Cancelado: fora dos totais.
module FinancialTitle
  extend ActiveSupport::Concern

  OPEN_STATUSES = %w[forecast pending overdue].freeze

  included do
    include Auditable
    include LabeledEnums
    include MoneyAttributes

    labeled_enum :status, forecast: "Previsto", pending: "Pendente", paid: "Pago", overdue: "Vencido", cancelled: "Cancelado"
    money_attribute :amount

    validates :description, :category, :competence, :due_on, presence: true
    validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :paid_on, presence: { message: "precisa ser informada para marcar como pago" }, if: :paid?

    before_validation { self.competence = competence&.beginning_of_month }
    before_validation :sync_status_with_payment
    before_validation :initial_status, on: :create

    scope :open, -> { where(status: OPEN_STATUSES) }
    scope :in_competence, ->(range) { where(competence: range.first.beginning_of_month..range.last) }
    scope :by_due, -> { order(:due_on, :created_at) }
  end

  def open? = status.in?(OPEN_STATUSES)

  # Competência no formulário como "2026-09" (input type="month").
  def competence_month
    competence&.strftime("%Y-%m")
  end

  def competence_month=(value)
    self.competence = value.present? ? Date.strptime(value.to_s, "%Y-%m") : nil
  rescue Date::Error
    self.competence = nil
  end

  def days_late(today = Date.current)
    open? && due_on < today ? (today - due_on).to_i : 0
  end

  # "Setembro/2026"
  def competence_label
    I18n.l(competence, format: "%B/%Y").capitalize if competence
  end

  def cancel!(reason = nil)
    update!(status: "cancelled", notes: [ notes, reason ].compact_blank.join("\n").presence)
  end

  private

  # Lançado à mão (status padrão): previsto se a competência é futura; vencido se já venceu.
  def initial_status
    return unless pending? && paid_on.blank?

    if due_on && due_on < Date.current then self.status = "overdue"
    elsif competence && competence > Date.current.beginning_of_month then self.status = "forecast"
    end
  end

  # Data de pagamento manda: com ela o título está pago; sem ela, não pode estar pago.
  def sync_status_with_payment
    if paid_on.present? && !cancelled?
      self.status = "paid"
    elsif paid? && paid_on.blank? && will_save_change_to_paid_on?
      self.status = due_on && due_on < Date.current ? "overdue" : "pending"
    end
  end
end
