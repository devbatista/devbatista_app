# Agente do Claude que trabalha para a DevBatista (docs/specs/escritorio-agentes): uma rotina
# agendada que acessa o Admin pelo MCP e se identifica pela chave. Aparece no escritório como um
# personagem na sua sala; as cores são as do sprite.
class Agent < ApplicationRecord
  include Auditable

  COLOR = /\A#\h{6}\z/
  # Agentes iniciais, na ordem das salas da planta (Agent.seed_defaults!).
  DEFAULTS = [
    { key: "ops", name: "Ops", title: "SRE", room: "Infra", outfit_color: "#0e7490", hair_color: "#1f2937", skin_color: "#e0ac69" },
    { key: "sol", name: "Sol", title: "SDR", room: "Comercial", outfit_color: "#f59e0b", hair_color: "#7c2d12", skin_color: "#f1c27d" },
    { key: "mia", name: "Mia", title: "Marketing", room: "Marketing", outfit_color: "#db2777", hair_color: "#facc15", skin_color: "#ffdbac" },
    { key: "leo", name: "Leo", title: "Tráfego pago", room: "Tráfego pago", outfit_color: "#16a34a", hair_color: "#111827", skin_color: "#8d5524" },
    { key: "fin", name: "Fin", title: "Financeiro", room: "Financeiro", outfit_color: "#6366f1", hair_color: "#78350f", skin_color: "#c68642" }
  ].freeze

  audited area: "agentes", activity: false

  has_many :events, class_name: "AgentEvent", dependent: :restrict_with_error
  has_many :orders, class_name: "AgentOrder", dependent: :restrict_with_error

  validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z][a-z0-9_]*\z/, message: "usa só letras minúsculas, números e _" }
  validates :name, :title, :room, presence: true
  validates :outfit_color, :hair_color, :skin_color, format: { with: COLOR, message: "precisa estar no formato #RRGGBB" }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  attr_writer :latest_event

  # Pode rodar mais de uma vez: só cria os que ainda não existem.
  def self.seed_defaults!
    DEFAULTS.each_with_index do |attrs, index|
      find_or_create_by!(key: attrs[:key]) { |agent| agent.assign_attributes(attrs.merge(position: index + 1)) }
    end
  end

  # Último evento de cada agente numa consulta só, para a planta.
  def self.preload_latest_events(agents)
    latest = AgentEvent.where(agent_id: agents.map(&:id)).select("DISTINCT ON (agent_id) *")
                       .order(:agent_id, created_at: :desc, id: :desc).index_by(&:agent_id)
    agents.each { |agent| agent.latest_event = latest[agent.id] }
  end

  def to_param
    key
  end

  def to_s
    name
  end

  def latest_event
    return @latest_event if defined?(@latest_event)

    @latest_event = events.recent.first
  end

  # Status do último evento. Sem evento, Ocioso; um pedido de aprovação já decidido também volta a
  # Ocioso, até a próxima execução do agente.
  def status
    event = latest_event
    return "idle" if event.nil? || (event.status_awaiting_approval? && !event.decision_pending?)

    event.status
  end

  def status_label
    AgentEvent::STATUS_LABELS.fetch(status)
  end

  def pending_approvals
    events.decision_pending.recent
  end

  # Ordens do painel: as pendentes e as concluídas hoje.
  def panel_orders
    orders.status_pending.or(orders.where(completed_at: Time.current.all_day)).includes(:user).recent
  end

  def reload(*)
    remove_instance_variable(:@latest_event) if defined?(@latest_event)
    super
  end

  # Planta e painel do escritório, para quem estiver com a página aberta. O painel vem como turbo-frame
  # com src, buscado com a sessão de quem vê, porque os botões dependem da permissão.
  def broadcast_office
    broadcast_replace_later_to :escritorio, target: ActionView::RecordIdentifier.dom_id(self, :desk), partial: "agents/desk", locals: { agent: self }
    %i[panel log].each do |part|
      broadcast_replace_later_to :escritorio, target: ActionView::RecordIdentifier.dom_id(self, part), partial: "agents/panel_frame",
                                              locals: { agent: self, part: part }
    end
  end
end
