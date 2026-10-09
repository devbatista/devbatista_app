# Troca os ids (UUID v7, com a data e o id antigo nos bits) por UUID v4 aleatório, o padrão
# do Postgres (gen_random_uuid()). Roda numa transação só e preserva os dados.
#
# - As chaves estrangeiras ficam com ON UPDATE CASCADE durante a troca: mudar o id de uma
#   linha já atualiza quem aponta para ela. Depois voltam à definição original.
# - Polimórficas e textos que guardam ids (caminho e chave anti-duplicidade das notificações,
#   campos *_id do histórico da auditoria) são reescritos antes, pelo mapa antigo → novo.
# - A ordem cronológica passa a vir do created_at (ApplicationRecord.implicit_order_column).
class RegenerateIdsAsUuidV4 < ActiveRecord::Migration[8.1]
  SKIP = %w[schema_migrations ar_internal_metadata].freeze
  UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

  POLYMORPHIC = {
    "active_storage_attachments" => { "record_id" => "record_type" },
    "activities" => { "subject_id" => "subject_type" },
    "apps" => { "hosting_id" => "hosting_type" },
    "audit_logs" => { "auditable_id" => "auditable_type" },
    "documents" => { "documentable_id" => "documentable_type" },
    "interactions" => { "subject_id" => "subject_type" },
    "notifications" => { "notifiable_id" => "notifiable_type" }
  }.freeze

  # Parâmetros de query com id nos caminhos guardados das notificações.
  QUERY_PARAMS = { "projeto" => "projects", "empresa" => "companies", "contrato" => "contracts",
                   "proposta" => "proposals", "fornecedor" => "suppliers", "lead" => "leads" }.freeze

  def up
    tables = connection.tables - SKIP
    foreign_keys = select_rows(<<~SQL)
      SELECT conrelid::regclass::text, conname, pg_get_constraintdef(oid)
      FROM pg_constraint WHERE contype = 'f' AND connamespace = 'public'::regnamespace
    SQL

    execute "ALTER TABLE audit_logs DISABLE TRIGGER audit_logs_no_update_delete"

    # 1. Novo id aleatório ao lado do atual, e o mapa atual → novo.
    tables.each { |table| execute "ALTER TABLE #{table} ADD COLUMN new_id uuid NOT NULL DEFAULT gen_random_uuid()" }
    maps = tables.index_with { |table| select_rows("SELECT id, new_id FROM #{table}").to_h }

    # 2. Polimórficas e textos, enquanto os ids atuais ainda existem.
    POLYMORPHIC.each do |table, columns|
      columns.each do |column, type_column|
        select_values("SELECT DISTINCT #{type_column} FROM #{table} WHERE #{type_column} IS NOT NULL").each do |type|
          target = type.safe_constantize&.table_name
          next unless target && tables.include?(target)

          execute "UPDATE #{table} t SET #{column} = r.new_id FROM #{target} r " \
                  "WHERE t.#{type_column} = #{quote(type)} AND r.id = t.#{column}"
        end
      end
    end
    rewrite_notifications(maps)
    rewrite_audit_changesets(maps)

    # 3. Troca dos ids, com as chaves estrangeiras propagando a mudança.
    foreign_keys.each do |table, name, definition|
      execute "ALTER TABLE #{table} DROP CONSTRAINT #{name}"
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{name} #{definition} ON UPDATE CASCADE"
    end
    tables.each { |table| execute "UPDATE #{table} SET id = new_id" }
    foreign_keys.each do |table, name, definition|
      execute "ALTER TABLE #{table} DROP CONSTRAINT #{name}"
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{name} #{definition}"
    end

    # 4. Padrão das chaves novas e limpeza.
    tables.each do |table|
      execute "ALTER TABLE #{table} DROP COLUMN new_id"
      execute "ALTER TABLE #{table} ALTER COLUMN id SET DEFAULT gen_random_uuid()"
    end
    execute "DROP FUNCTION IF EXISTS uuid_v7()"
    execute "DROP FUNCTION IF EXISTS uuid_v7_at(timestamptz, bigint)"

    execute "ALTER TABLE audit_logs ENABLE TRIGGER audit_logs_no_update_delete"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Caminho ("/operations/projects/<id>", "?projeto=<id>") e chave anti-duplicidade
  # ("contract-<id>-2026-10-17-15d"), para os alertas já enviados não voltarem.
  def rewrite_notifications(maps)
    select_rows("SELECT id, path, dedup_key, notifiable_type FROM notifications").each do |id, path, dedup, type|
      new_path = path&.gsub(%r{/([a-z-]+)/(#{UUID})}) do
        (uuid = maps.dig(Regexp.last_match(1).tr("-", "_"), Regexp.last_match(2))) ? "/#{Regexp.last_match(1)}/#{uuid}" : Regexp.last_match(0)
      end
      new_path = new_path&.gsub(/([?&])(#{QUERY_PARAMS.keys.join('|')})=(#{UUID})/) do
        (uuid = maps.dig(QUERY_PARAMS[Regexp.last_match(2)], Regexp.last_match(3))) ? "#{Regexp.last_match(1)}#{Regexp.last_match(2)}=#{uuid}" : Regexp.last_match(0)
      end
      new_dedup = dedup&.sub(/\A([a-z]+)-(#{UUID})/) do
        table = type&.safe_constantize&.table_name || Regexp.last_match(1).pluralize
        (uuid = maps.dig(table, Regexp.last_match(2))) ? "#{Regexp.last_match(1)}-#{uuid}" : Regexp.last_match(0)
      end
      next if new_path == path && new_dedup == dedup

      execute "UPDATE notifications SET path = #{quote(new_path)}, dedup_key = #{quote(new_dedup)} WHERE id = #{quote(id)}"
    end
  end

  # Campos *_id do histórico ("role_id" => [<id>, <id>]) passam a mostrar o novo id.
  def rewrite_audit_changesets(maps)
    select_rows("SELECT id, auditable_type, changeset::text FROM audit_logs WHERE changeset::text LIKE '%\\_id\"%'").each do |id, type, json|
      model = type&.safe_constantize
      next unless model.respond_to?(:reflect_on_all_associations)

      changeset = JSON.parse(json)
      changed = false
      changeset.each do |field, values|
        reflection = model.reflect_on_all_associations(:belongs_to).find { |r| r.foreign_key.to_s == field }
        next unless reflection

        convert = lambda do |value, side|
          next value unless value.is_a?(String) && value.match?(/\A#{UUID}\z/)

          target = if reflection.polymorphic?
            types = changeset[reflection.foreign_type.to_s]
            (types.is_a?(Array) ? types[side] : types)&.safe_constantize&.table_name
          else
            reflection.klass.table_name
          end
          maps.dig(target, value) || value
        end
        new_values = values.is_a?(Array) ? values.each_with_index.map { |value, side| convert.call(value, side) } : convert.call(values, 1)
        changed ||= new_values != values
        changeset[field] = new_values
      end
      execute "UPDATE audit_logs SET changeset = #{quote(changeset.to_json)}::jsonb WHERE id = #{quote(id)}" if changed
    end
  end

  def quote(value)
    connection.quote(value)
  end
end
