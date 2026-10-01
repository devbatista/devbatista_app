# Garante no banco que a trilha de auditoria é imutável: nenhum UPDATE ou DELETE passa.
class ProtectAuditLogs < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION audit_logs_immutable() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'audit_logs é somente inserção';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER audit_logs_no_update_delete
        BEFORE UPDATE OR DELETE ON audit_logs
        FOR EACH ROW EXECUTE FUNCTION audit_logs_immutable();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER audit_logs_no_update_delete ON audit_logs;
      DROP FUNCTION audit_logs_immutable();
    SQL
  end
end
