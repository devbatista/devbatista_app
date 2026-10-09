# Uma execução da rotina de recorrências (diária ou "Executar rotina agora").
class RecurrenceRun < ApplicationRecord
  belongs_to :user, optional: true

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }

  def duration_seconds
    finished_at && (finished_at - started_at).round
  end

  def warning_list
    warnings.to_s.split("\n").compact_blank
  end
end
