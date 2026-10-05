# Projeto de um cliente (RF 18): previsão, orçamento e progresso.
# Atrasado = previsão ultrapassada e status diferente de Concluído ou Cancelado; a rotina
# diária avisa o responsável e os administradores (OperationAlertsJob).
# O progresso é informado à mão ou calculado pelas tarefas concluídas.
class Project < ApplicationRecord
  include Auditable
  include LabeledEnums
  include MoneyAttributes

  ACTIVE_STATUSES = %w[planning in_progress paused waiting_client].freeze
  CLOSED_STATUSES = %w[done cancelled].freeze

  audited area: "projetos"
  labeled_enum :status, planning: "Planejamento", in_progress: "Em andamento", paused: "Pausado",
                        waiting_client: "Aguardando cliente", done: "Concluído", cancelled: "Cancelado"
  money_attribute :budget

  belongs_to :company
  belongs_to :user
  belongs_to :contract, optional: true
  belongs_to :proposal, optional: true
  has_many :tasks, dependent: :destroy
  has_many :time_entries, dependent: :restrict_with_error
  has_many :documents, as: :documentable, dependent: :restrict_with_error

  validates :name, :due_date, presence: true
  validates :budget_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :progress, numericality: { only_integer: true, in: 0..100 }
  validate :due_after_start
  validate :links_from_same_company

  before_validation { self.progress ||= 0 }
  before_save :compute_progress, if: :progress_from_tasks?
  before_save :set_closed_on

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :late, ->(today = Date.current) { where.not(status: CLOSED_STATUSES).where(due_date: ...today) }
  scope :by_name, -> { order(:name) }
  scope :search, lambda { |term|
    joins(:company).where("unaccent(projects.name) ILIKE unaccent(:q) OR unaccent(companies.trade_name) ILIKE unaccent(:q)",
                          q: "%#{sanitize_sql_like(term.to_s.strip)}%")
  }

  def closed? = status.in?(CLOSED_STATUSES)
  def active? = status.in?(ACTIVE_STATUSES)

  def late?(today = Date.current)
    !closed? && due_date.present? && due_date < today
  end

  def days_late(today = Date.current)
    (today - due_date).to_i
  end

  def days_left(today = Date.current)
    (due_date - today).to_i
  end

  # Progresso pelas tarefas: concluídas ÷ total, arredondado.
  def tasks_progress
    total = tasks.size
    total.zero? ? 0 : (tasks.count(&:done?) * 100.0 / total).round
  end

  # Chamado pelas tarefas quando uma delas muda de status, entra ou sai do projeto.
  def refresh_progress!
    tasks.reset
    update!(progress: tasks_progress) if progress_from_tasks? && progress != tasks_progress
  end

  def logged_minutes
    time_entries.sum(:minutes)
  end

  # Estimativa do projeto = soma das estimativas das tarefas.
  def estimated_minutes
    tasks.sum(:estimated_minutes)
  end

  def activity_name
    "o projeto #{name}"
  end

  def to_s
    name
  end

  private

  def compute_progress
    self.progress = tasks_progress
  end

  def set_closed_on
    self.closed_on = closed? ? (closed_on || Date.current) : nil
  end

  def due_after_start
    errors.add(:due_date, "precisa ser depois da data inicial") if start_date && due_date && due_date < start_date
  end

  def links_from_same_company
    errors.add(:contract, "é de outra empresa") if contract && contract.company_id != company_id
    errors.add(:proposal, "é de outra empresa") if proposal && proposal.company_id != company_id
  end
end
