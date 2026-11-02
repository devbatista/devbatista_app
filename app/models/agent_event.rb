# O que um agente registrou pelo MCP (registrar_evento): status, título, resumo e, quando precisa de
# aprovação, a decisão do administrador. O agente lê a decisão na próxima execução (ler_pendencias).
# O status atual do agente é o do último evento (Agent#status).
class AgentEvent < ApplicationRecord
  include Auditable
  include LabeledEnums

  PAYLOAD_LIMIT = 20.kilobytes
  DECISIONS = %w[approved rejected].freeze

  audited area: "agentes", ignore: %w[decision_read_at], activity: false
  labeled_enum :status, {
    working: "Trabalhando", idle: "Ocioso", awaiting_approval: "Aguardando aprovação", done: "Concluído", error: "Erro"
  }, prefix: :status
  labeled_enum :decision, { pending: "Pendente", approved: "Aprovado", rejected: "Rejeitado" }, prefix: :decision,
                                                                                                validate: { allow_nil: true }

  belongs_to :agent
  belongs_to :decided_by, class_name: "User", optional: true

  # Pedir aprovação e ficar aguardando são a mesma coisa: um implica o outro.
  before_validation :sync_approval, on: :create

  validates :title, presence: true, length: { maximum: 120 }
  validates :summary, :decision_note, length: { maximum: 5000 }
  validates :decision, presence: true, if: :needs_approval?
  validates :decision, absence: true, unless: :needs_approval?
  validate :payload_size

  # Criação e alteração (decisão). Num callback só: after_create_commit e after_update_commit com o
  # mesmo método ficariam só com o último.
  after_commit :broadcast_office, on: %i[create update]

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :today, -> { where(created_at: Time.current.all_day) }
  scope :unread_decisions, -> { where(decision: DECISIONS, decision_read_at: nil) }

  def to_s
    title
  end

  # Aprovar ou rejeitar, uma vez só. Com o evento travado, para dois cliques não decidirem duas vezes.
  def decide!(choice, by:, note: nil)
    with_lock do
      errors.add(:decision, "inválida") unless choice.in?(DECISIONS)
      errors.add(:decision, "já foi registrada") unless decision_pending?
      raise ActiveRecord::RecordInvalid, self if errors.any?

      update!(decision: choice, decided_at: Time.current, decided_by: by, decision_note: note.presence)
    end
  end

  private

  def sync_approval
    self.needs_approval = true if status_awaiting_approval?
    return unless needs_approval?

    self.status = "awaiting_approval"
    self.decision ||= "pending"
  end

  def payload_size
    errors.add(:payload, "passa de 20 KB") if payload.present? && payload.to_json.bytesize > PAYLOAD_LIMIT
  end

  def broadcast_office
    agent.broadcast_office
  end
end
