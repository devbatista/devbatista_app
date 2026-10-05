# Lançamento de horas trabalhadas (RF 20). Cliente e duração são obrigatórios; projeto,
# tarefa e chamado são opcionais e, quando informados, precisam ser do mesmo cliente.
# Perfis com permissão "Próprio" só veem e editam os próprios lançamentos (TimeEntryPolicy).
class TimeEntry < ApplicationRecord
  include Auditable

  MAX_MINUTES = 24 * 60

  audited area: "horas"

  belongs_to :user
  belongs_to :company
  belongs_to :project, optional: true
  belongs_to :task, optional: true
  belongs_to :ticket, optional: true

  validates :worked_on, presence: true
  validates :minutes, presence: { message: "precisa ser informada (hh:mm)" }
  validates :minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_MINUTES,
                                      message: "precisa ficar entre 00:01 e 24:00" }, allow_nil: true
  validate :links_from_same_company

  before_validation :fill_links

  scope :recent, -> { order(worked_on: :desc, id: :desc) }
  scope :search, lambda { |term|
    left_joins(:task).where("unaccent(time_entries.description) ILIKE unaccent(:q) OR unaccent(tasks.title) ILIKE unaccent(:q)",
                            q: "%#{sanitize_sql_like(term.to_s.strip)}%")
  }

  # Aceita "1:30", "01:30", "1h30", "1h", "90min", "1,5" e "1.5" (horas).
  def self.parse_duration(text)
    value = text.to_s.strip.downcase.delete(" ")
    case value
    when /\A(\d{1,2}):([0-5]\d)\z/, /\A(\d{1,2})h([0-5]\d)?(min)?\z/ then Regexp.last_match(1).to_i * 60 + Regexp.last_match(2).to_i
    when /\A(\d+)min\z/ then Regexp.last_match(1).to_i
    when /\A\d+([.,]\d+)?\z/ then (value.tr(",", ".").to_f * 60).round
    end
  end

  # 210 → "3h30"; 240 → "4h" (ou "4h00" com pad: true).
  def self.format_minutes(minutes, pad: false)
    hours, mins = minutes.to_i.divmod(60)
    mins.zero? && !pad ? "#{hours}h" : format("%dh%02d", hours, mins)
  end

  # Duração em hh:mm no formulário; guardada em minutos.
  def duration
    @duration || (minutes && format("%02d:%02d", *minutes.divmod(60)))
  end

  def duration=(text)
    @duration = text
    self.minutes = self.class.parse_duration(text)
  end

  def activity_name
    "o lançamento de #{self.class.format_minutes(minutes)} em #{target_name}"
  end

  def to_s
    "#{self.class.format_minutes(minutes)} · #{target_name}"
  end

  # Onde as horas foram gastas, do mais específico para o mais geral.
  def target_name
    task&.title || ticket&.then { |t| "chamado #{t.code}" } || project&.name || company&.trade_name
  end

  private

  def activity_description(action, changes)
    action == "create" ? "Registrou #{self.class.format_minutes(minutes)} em #{target_name}" : super
  end

  def fill_links
    self.project ||= task&.project
    self.company ||= project&.company || ticket&.company
  end

  def links_from_same_company
    errors.add(:project, "é de outro cliente") if project && project.company_id != company_id
    errors.add(:task, "é de outro projeto") if task && task.project_id != project_id
    errors.add(:ticket, "é de outro cliente") if ticket && ticket.company_id != company_id
  end
end
