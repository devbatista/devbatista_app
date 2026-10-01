# Grava na trilha de auditoria toda criação, alteração e exclusão do model.
#
#   class Company < ApplicationRecord
#     include Auditable
#     audited area: "clientes"
#   end
#
# Uma alteração que muda o campo status é registrada como "status_change".
# Os campos listados em `ignore` não entram na trilha e, sozinhos, não geram registro.
module Auditable
  extend ActiveSupport::Concern

  ALWAYS_IGNORED = %w[id updated_at created_at].freeze

  included do
    class_attribute :audit_area, instance_writer: false
    class_attribute :audit_ignored, instance_writer: false, default: []

    after_create { write_audit("create", audit_changes(saved_changes)) }
    after_update do
      changes = audit_changes(saved_changes)
      write_audit(changes.key?("status") ? "status_change" : "update", changes) if changes.any?
    end
    after_destroy { write_audit("destroy", audit_changes(attributes.transform_values { |v| [ v, nil ] })) }
  end

  class_methods do
    def audited(area:, ignore: [])
      self.audit_area = area
      self.audit_ignored = ignore.map(&:to_s)
    end
  end

  private

  def audit_changes(changes)
    changes.except(*ALWAYS_IGNORED, *audit_ignored)
  end

  def write_audit(action, changes)
    AuditLog.record!(action: action, area: audit_area, record: self, changes: changes)
  end
end
