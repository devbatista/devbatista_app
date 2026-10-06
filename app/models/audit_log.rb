# Trilha de auditoria imutável: depois de gravado, o registro não muda nem sai.
# O banco também bloqueia UPDATE e DELETE (ver migration ProtectAuditLogs).
class AuditLog < ApplicationRecord
  ACTIONS = {
    "create" => "Criação",
    "update" => "Alteração",
    "destroy" => "Exclusão",
    "status_change" => "Mudança de status",
    "login" => "Login",
    "login_failed" => "Falha de login",
    "logout" => "Logout",
    "password_change" => "Troca de senha"
  }.freeze

  belongs_to :user, optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  validates :action, inclusion: { in: ACTIONS.keys }
  validates :area, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.record!(action:, area:, record: nil, label: nil, changes: {}, user: Current.user)
    create!(
      action: action,
      area: area,
      auditable: record,
      auditable_label: label || record&.to_s,
      changeset: changes,
      user: user,
      ip_address: Current.ip_address
    )
  end

  def readonly?
    persisted?
  end

  def action_name
    ACTIONS.fetch(action, action)
  end

  # Nome do model na interface ("Usuário" em vez de "User").
  def auditable_type_name
    auditable_type&.safe_constantize&.model_name&.human || auditable_type
  end

  # Campos alterados prontos para exibir: [rótulo, antes, depois].
  # Na criação só existe o valor novo; na exclusão, só o anterior.
  def readable_changes
    model = auditable_type&.safe_constantize
    changeset.map do |field, change|
      label = model.respond_to?(:human_attribute_name) ? model.human_attribute_name(field) : field
      before, after = change.is_a?(Array) && change.size == 2 ? change : [ nil, change ]
      [ label, before, after ]
    end
  end
end
