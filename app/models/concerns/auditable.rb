# Grava toda criação, alteração, exclusão e mudança de status do model em dois lugares:
# - AuditLog: trilha técnica e imutável, com valor anterior e novo (RF 41);
# - Activity: histórico de negócio legível, mostrado na Visão 360º e no dashboard.
#
#   class Company < ApplicationRecord
#     include Auditable
#     audited area: "clientes"
#   end
#
# Uma alteração que muda o campo status é registrada como "status_change".
# Os campos listados em `ignore` não entram na trilha e, sozinhos, não geram registro.
# `activity: false` desliga o histórico de negócio (ex.: usuários).
#
# O model pode sobrescrever:
#   activity_name     nome com artigo, para as frases ("o contrato #104")
#   activity_company  empresa a que o evento pertence (para a Visão 360º)
module Auditable
  extend ActiveSupport::Concern

  ALWAYS_IGNORED = %w[id updated_at created_at].freeze

  included do
    class_attribute :audit_area, instance_writer: false
    class_attribute :audit_ignored, instance_writer: false, default: []
    class_attribute :audit_activity, instance_writer: false, default: true

    after_create { write_audit("create", audit_changes(saved_changes)) }
    after_update do
      changes = audit_changes(saved_changes)
      write_audit(changes.key?("status") ? "status_change" : "update", changes) if changes.any?
    end
    after_destroy { write_audit("destroy", audit_changes(attributes.transform_values { |v| [ v, nil ] })) }
  end

  class_methods do
    def audited(area:, ignore: [], activity: true)
      self.audit_area = area
      self.audit_ignored = ignore.map(&:to_s)
      self.audit_activity = activity
    end
  end

  def activity_name
    "#{self.class.model_name.human.downcase} #{self}"
  end

  def activity_company
    return self if is_a?(Company)

    respond_to?(:company) ? company : nil
  end

  private

  def audit_changes(changes)
    changes.except(*ALWAYS_IGNORED, *audit_ignored)
  end

  def write_audit(action, changes)
    AuditLog.record!(action: action, area: audit_area, record: self, changes: changes)
    return unless audit_activity

    Activity.create!(
      action: action, area: audit_area, user: Current.user, subject: (action == "destroy" ? nil : self),
      company: (activity_company unless action == "destroy" && is_a?(Company)),
      description: activity_description(action, changes)
    )
  end

  def activity_description(action, changes)
    case action
    when "create" then "Criou #{activity_name}"
    when "destroy" then "Excluiu #{activity_name}"
    when "status_change"
      from, to = changes["status"]
      "Mudou o status de #{activity_name}: #{status_text(from)} → #{status_text(to)}"
    else
      fields = changes.keys.map { |field| self.class.human_attribute_name(field.delete_suffix("_cents")) }
      "Alterou #{activity_name} (#{fields.to_sentence})"
    end
  end

  def status_text(value)
    labels = self.class.const_defined?(:STATUS_LABELS) ? self.class::STATUS_LABELS : {}
    labels.fetch(value.to_s, value.to_s.presence || "—")
  end
end
