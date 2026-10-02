# Interação registrada à mão com um lead ou numa oportunidade.
class Interaction < ApplicationRecord
  include LabeledEnums

  labeled_enum :kind, call: "Ligação", whatsapp: "WhatsApp", email: "E-mail", meeting: "Reunião", note: "Nota"

  belongs_to :subject, polymorphic: true
  belongs_to :user

  validates :occurred_on, :notes, presence: true
  validates :subject_type, inclusion: { in: %w[Lead Opportunity] }

  scope :recent, -> { order(occurred_on: :desc, created_at: :desc) }
end
