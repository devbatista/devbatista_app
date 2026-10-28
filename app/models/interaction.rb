# Interação registrada à mão com um lead ou numa oportunidade. As do tipo WhatsApp com conversa
# são automáticas: uma por dia de conversa (WhatsappInteractionJob).
class Interaction < ApplicationRecord
  include LabeledEnums

  labeled_enum :kind, call: "Ligação", whatsapp: "WhatsApp", email: "E-mail", meeting: "Reunião", note: "Nota"

  belongs_to :subject, polymorphic: true
  belongs_to :user
  belongs_to :whatsapp_conversation, optional: true

  validates :occurred_on, :notes, presence: true
  validates :subject_type, inclusion: { in: %w[Lead Opportunity] }

  scope :recent, -> { order(occurred_on: :desc, created_at: :desc) }

  def automatic?
    whatsapp_conversation_id.present?
  end
end
