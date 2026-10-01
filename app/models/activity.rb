# Histórico de negócio em linguagem natural ("Ana Souza alterou o status do contrato #104").
# Gravado junto com o AuditLog pelo concern Auditable.
class Activity < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :company, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :area, :action, :description, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def readonly?
    persisted?
  end
end
