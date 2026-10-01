class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :user, foreign_key: true
      t.string :action, null: false
      t.string :area, null: false
      t.string :auditable_type
      t.bigint :auditable_id
      t.string :auditable_label
      t.jsonb :changeset, null: false, default: {}
      t.string :ip_address

      t.datetime :created_at, null: false
    end
    add_index :audit_logs, [ :auditable_type, :auditable_id ]
    add_index :audit_logs, :created_at
    add_index :audit_logs, [ :area, :action ]
  end
end
