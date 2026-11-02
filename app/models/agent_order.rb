# Ordem deixada pelo administrador no escritório. O agente a lê na próxima execução (ler_pendencias,
# que grava delivered_at na primeira leitura) e a conclui com a resposta (concluir_pendencia).
class AgentOrder < ApplicationRecord
  include Auditable
  include LabeledEnums

  audited area: "agentes", ignore: %w[delivered_at], activity: false
  labeled_enum :status, { pending: "Pendente", completed: "Concluída" }, prefix: :status

  belongs_to :agent
  belongs_to :user

  validates :body, presence: true, length: { maximum: 5000 }
  validates :response, length: { maximum: 5000 }
  validates :response, presence: true, if: :status_completed?

  after_commit :broadcast_office, on: %i[create update]

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def to_s
    body.truncate(60)
  end

  # Concluir uma vez só, com o registro travado.
  def complete!(response)
    with_lock do
      errors.add(:status, "já está concluída") if status_completed?
      raise ActiveRecord::RecordInvalid, self if errors.any?

      update!(status: "completed", response: response, completed_at: Time.current)
    end
  end

  private

  def broadcast_office
    agent.broadcast_office
  end
end
