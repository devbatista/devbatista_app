# Tarefa de um projeto (RF 19), vista em lista ou no quadro por status.
# A tela compara a estimativa com as horas registradas na tarefa.
# Atrasada = prazo ultrapassado e não concluída; a rotina diária avisa o responsável.
class Task < ApplicationRecord
  include Auditable
  include LabeledEnums

  audited area: "projetos"
  labeled_enum :status, backlog: "Backlog", todo: "A fazer", in_progress: "Em andamento", review: "Em revisão", done: "Concluída"
  labeled_enum :priority, low: "Baixa", normal: "Normal", high: "Alta", urgent: "Urgente"

  belongs_to :project
  belongs_to :user, optional: true
  has_many :time_entries, dependent: :nullify

  validates :title, presence: true
  validates :estimated_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  before_save :set_completed_on
  after_save :refresh_project_progress, if: -> { saved_change_to_status? || saved_change_to_project_id? }
  after_destroy :refresh_project_progress

  scope :pending, -> { where.not(status: "done") }
  scope :late, ->(today = Date.current) { pending.where(due_on: ...today) }
  scope :by_due, -> { order(Arel.sql("tasks.due_on IS NULL"), :due_on, :id) }
  scope :search, ->(term) { where("unaccent(tasks.title) ILIKE unaccent(?)", "%#{sanitize_sql_like(term.to_s.strip)}%") }

  # Estimativa em horas no formulário (aceita 8, "1,5" e "1.5"); guardada em minutos.
  def estimated_hours
    estimated_minutes && (estimated_minutes / 60.0)
  end

  def estimated_hours=(value)
    hours = value.to_s.strip.tr(",", ".")
    self.estimated_minutes = hours.match?(/\A\d+(\.\d+)?\z/) ? (hours.to_f * 60).round : nil
  end

  def late?(today = Date.current)
    !done? && due_on.present? && due_on < today
  end

  def days_late(today = Date.current)
    (today - due_on).to_i
  end

  # Horas registradas acima da estimativa aparecem em destaque.
  def over_estimate?(logged)
    estimated_minutes.to_i.positive? && logged > estimated_minutes
  end

  def activity_name
    "a tarefa #{title}"
  end

  def activity_company
    project&.company
  end

  def to_s
    title
  end

  private

  def set_completed_on
    self.completed_on = done? ? (completed_on || Date.current) : nil
  end

  def refresh_project_progress
    return if destroyed_by_association

    project.refresh_progress!
    Project.find_by(id: project_id_before_last_save)&.refresh_progress! if saved_change_to_project_id? && project_id_before_last_save
  end
end
