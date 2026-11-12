# "Feito" de um item da lista Próximos passos, pela tela ou pela tool concluir_passo do MCP.
#
# Grava o que foi feito como interação no histórico (como registrar_interacao) e, na mesma
# transação, define o novo próximo passo (texto + data e hora) ou marca o registro como perdido
# com um dos motivos de perda. Regra: nenhum item sai da lista sem um dos dois.
#
# Quem chama confere a permissão (update? no registro, create? na interação).
class NextStepCompletion
  include ActiveModel::Model
  include ActiveModel::Attributes

  OUTCOMES = %w[next_step lost].freeze
  RULE = "Defina o próximo passo (texto e data/hora) ou marque como perdido: nenhum item sai da lista sem um dos dois".freeze
  HUMAN_NAMES = {
    "notes" => "O que foi feito", "kind" => "Tipo de interação", "next_step" => "Próximo passo",
    "next_step_on" => "Data e hora do próximo passo", "lost_reason" => "Motivo da perda"
  }.freeze

  attribute :notes, :string
  attribute :kind, :string
  attribute :outcome, :string
  attribute :next_step, :string
  attribute :next_step_on # NextStepSchedulable.cast: só a data vale às 09:00
  attribute :lost_reason, :string
  attribute :lost_details, :string

  attr_reader :record, :user, :interaction

  validates :notes, presence: true
  validates :kind, inclusion: { in: ->(_) { Interaction.kinds.keys } }
  validate :record_open
  validate :outcome_chosen
  validates :next_step, :next_step_on, presence: true, if: :scheduling?
  validates :lost_reason, presence: true, if: :losing?
  validates :lost_reason, inclusion: { in: ->(_) { Setting[:loss_reasons] }, message: "não está na lista de motivos" },
                          if: -> { losing? && lost_reason.present? }

  def self.human_attribute_name(attribute, options = {})
    HUMAN_NAMES.fetch(attribute.to_s) { super }
  end

  def initialize(record:, user:, **attributes)
    @record = record
    @user = user
    super(**attributes)
  end

  def next_step_on=(value)
    super(NextStepSchedulable.cast(value))
  end

  def scheduling? = outcome == "next_step"
  def losing? = outcome == "lost"

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      @interaction = record.interactions.create!(kind: kind, notes: notes, occurred_on: Date.current, user: user)
      if losing?
        record.mark_lost!(reason: lost_reason, details: lost_details.presence)
      else
        record.update!(next_step: next_step, next_step_on: next_step_on)
      end
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.full_messages.each { |message| errors.add(:base, message) }
    false
  end

  private

  def record_open
    errors.add(:base, "Só registros em aberto têm próximo passo") unless record.open?
  end

  def outcome_chosen
    errors.add(:base, RULE) unless outcome.in?(OUTCOMES)
  end
end
