# Oportunidade: negócio em andamento com um cliente (ou com um lead convertido em cliente).
# Base da previsão comercial: previsão ponderada = valor estimado × probabilidade (RF 9).
class Opportunity < ApplicationRecord
  include Auditable
  include LabeledEnums
  include Losable
  include MoneyAttributes

  # Probabilidade sugerida pela etapa (premissa adotada; editável em cada oportunidade).
  STAGE_PROBABILITY = { "meeting" => 25, "proposal" => 50, "negotiation" => 75, "won" => 100, "lost" => 0 }.freeze
  OPEN_STAGES = %w[meeting proposal negotiation].freeze

  audited area: "comercial"
  labeled_enum :stage, { meeting: "Reunião", proposal: "Proposta", negotiation: "Negociação", won: "Fechado", lost: "Perdido" }, prefix: :stage
  money_attribute :estimated_value

  belongs_to :lead, optional: true
  belongs_to :company
  belongs_to :service, optional: true
  belongs_to :user
  has_many :proposals, dependent: :nullify
  has_many :interactions, as: :subject, dependent: :destroy

  validates :title, presence: true
  validates :estimated_value_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :probability, numericality: { only_integer: true, in: 0..100 }

  before_validation do
    self.estimated_value_cents ||= 0
    self.probability ||= STAGE_PROBABILITY.fetch(stage.to_s, 25)
  end
  before_save :suggest_probability, if: :will_save_change_to_stage?
  before_save :set_closed_on

  scope :open, -> { where(stage: OPEN_STAGES) }
  scope :search, ->(term) { where("unaccent(opportunities.title) ILIKE unaccent(?)", "%#{sanitize_sql_like(term.to_s.strip)}%") }

  def lost? = stage_lost?
  def open? = stage.in?(OPEN_STAGES)

  def weighted_cents
    (estimated_value_cents * probability / 100.0).round
  end

  def activity_name
    "a oportunidade #{title}"
  end

  def to_s
    title
  end

  private

  def status_attribute = :stage

  # Ao mudar de etapa, a probabilidade acompanha a sugestão da etapa, a menos que a
  # pessoa tenha informado outra no mesmo salvamento.
  def suggest_probability
    fixed = stage_won? || stage_lost?
    self.probability = STAGE_PROBABILITY.fetch(stage) if fixed || !will_save_change_to_probability?
  end

  def set_closed_on
    self.closed_on = (stage_won? || stage_lost?) ? (closed_on || Date.current) : nil
  end
end
