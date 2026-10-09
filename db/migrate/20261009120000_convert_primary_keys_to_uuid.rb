# Troca todas as chaves (primárias, estrangeiras e polimórficas) de bigint para UUID v7,
# preservando os dados. Roda numa transação só: ou converte tudo, ou nada.
#
# - O novo id de cada linha é um UUID v7 montado com o created_at e o id antigo, para a
#   ordem por id continuar cronológica (e, no mesmo milissegundo, na ordem antiga).
# - Linhas novas recebem uuid_v7() (função própria: o Postgres 17 local não tem uuidv7()).
# - Índices, checks e chaves estrangeiras são lidos do banco antes e recriados depois.
# - Textos que guardam ids também mudam: caminho e chave anti-duplicidade das notificações
#   e os campos *_id do histórico da auditoria (com o trigger de imutabilidade desligado).
class ConvertPrimaryKeysToUuid < ActiveRecord::Migration[8.1]
  SKIP = %w[schema_migrations ar_internal_metadata].freeze

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
    create_functions
    tables = connection.tables - SKIP
    foreign_keys = select_rows(<<~SQL)
      SELECT c.conrelid::regclass::text, c.conname, a.attname, c.confrelid::regclass::text, pg_get_constraintdef(c.oid)
      FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
      WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace
    SQL
    constraints = select_rows(<<~SQL)
      SELECT conrelid::regclass::text, conname, pg_get_constraintdef(oid)
      FROM pg_constraint WHERE contype IN ('c', 'u', 'x') AND connamespace = 'public'::regnamespace
    SQL
    indexes = select_values(<<~SQL)
      SELECT pg_get_indexdef(i.indexrelid) FROM pg_index i
      JOIN pg_class t ON t.oid = i.indrelid JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE n.nspname = 'public' AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
    SQL
    references = foreign_keys.map { |table, _, column, target, _| [ table, column, target ] }
    polymorphic = POLYMORPHIC.flat_map { |table, columns| columns.map { |column, type| [ table, column, type ] } }

    execute "ALTER TABLE audit_logs DISABLE TRIGGER audit_logs_no_update_delete"

    # 1. Novo id de cada linha, ao lado do antigo.
    tables.each do |table|
      moment = column_exists?(table, :created_at) ? "created_at AT TIME ZONE 'UTC'" : "now()"
      add_column table, :uuid_id, :uuid
      execute "UPDATE #{table} SET uuid_id = uuid_v7_at(#{moment}, id)"
    end
    maps = tables.index_with { |table| select_rows("SELECT id, uuid_id FROM #{table}").to_h { |old, new| [ old.to_i, new ] } }

    # 2. Referências: chaves estrangeiras e polimórficas apontam para o novo id.
    references.each do |table, column, target|
      add_column table, "#{column}_uuid", :uuid
      execute "UPDATE #{table} t SET #{column}_uuid = r.uuid_id FROM #{target} r WHERE r.id = t.#{column}"
    end
    polymorphic.each do |table, column, type_column|
      add_column table, "#{column}_uuid", :uuid
      select_values("SELECT DISTINCT #{type_column} FROM #{table} WHERE #{type_column} IS NOT NULL").each do |type|
        target = type.safe_constantize&.table_name
        next unless target && tables.include?(target)

        execute "UPDATE #{table} t SET #{column}_uuid = r.uuid_id FROM #{target} r " \
                "WHERE t.#{type_column} = #{quote(type)} AND r.id = t.#{column}"
      end
    end

    # 3. Textos que guardam ids.
    rewrite_notifications(maps)
    rewrite_audit_changesets(maps)

    # 4. Troca das colunas.
    foreign_keys.each { |table, name, *| execute "ALTER TABLE #{table} DROP CONSTRAINT #{name}" }
    (references.map { |table, column, _| [ table, column ] } + polymorphic.map { |table, column, _| [ table, column ] }).uniq.each do |table, column|
      required = !connection.columns(table).find { |c| c.name == column }.null
      remove_column table, column
      rename_column table, "#{column}_uuid", column
      change_column_null table, column, false if required
    end
    tables.each do |table|
      execute "ALTER TABLE #{table} DROP COLUMN id"
      rename_column table, :uuid_id, :id
      execute "ALTER TABLE #{table} ALTER COLUMN id SET NOT NULL, ALTER COLUMN id SET DEFAULT uuid_v7(), ADD PRIMARY KEY (id)"
    end

    # 5. Índices, constraints e chaves estrangeiras de volta (os que caíram com as colunas).
    indexes.each { |definition| execute definition.sub(/INDEX /, "INDEX IF NOT EXISTS ") }
    constraints.each do |table, name, definition|
      next if select_value("SELECT 1 FROM pg_constraint WHERE conname = #{quote(name)} AND conrelid = #{quote(table)}::regclass")

      execute "ALTER TABLE #{table} ADD CONSTRAINT #{name} #{definition}"
    end
    foreign_keys.each { |table, name, _, _, definition| execute "ALTER TABLE #{table} ADD CONSTRAINT #{name} #{definition}" }

    execute "ALTER TABLE audit_logs ENABLE TRIGGER audit_logs_no_update_delete"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def create_functions
    execute <<~SQL
      -- UUID v7 com o instante e um número fixos: usado na conversão das linhas existentes.
      CREATE OR REPLACE FUNCTION uuid_v7_at(ts timestamptz, seq bigint) RETURNS uuid
      LANGUAGE sql IMMUTABLE AS $$
        SELECT encode(
          substring(int8send(floor(extract(epoch FROM ts) * 1000)::bigint) FROM 3)
          || decode('7000', 'hex')
          || set_byte(int8send(seq), 0, (get_byte(int8send(seq), 0) & 63) | 128),
          'hex')::uuid
      $$;

      -- UUID v7 (RFC 9562): milissegundos do relógio + bits aleatórios. Padrão das chaves primárias.
      CREATE OR REPLACE FUNCTION uuid_v7() RETURNS uuid
      LANGUAGE plpgsql VOLATILE AS $$
      DECLARE
        bytes bytea := uuid_send(gen_random_uuid());
      BEGIN
        bytes := overlay(bytes PLACING substring(int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3) FROM 1 FOR 6);
        bytes := set_byte(bytes, 6, (get_byte(bytes, 6) & 15) | 112);
        RETURN encode(bytes, 'hex')::uuid;
      END
      $$;
    SQL
  end

  # Caminho ("/operations/projects/12", "?projeto=12") e chave anti-duplicidade
  # ("contract-1-2026-10-17-15d"), para os alertas já enviados não voltarem.
  def rewrite_notifications(maps)
    select_rows("SELECT id, path, dedup_key, notifiable_type, notifiable_id FROM notifications").each do |id, path, dedup, type, notifiable_id|
      new_path = path&.gsub(%r{/([a-z-]+)/(\d+)(?=/|\?|\z)}) do
        table = Regexp.last_match(1).tr("-", "_")
        (uuid = maps.dig(table, Regexp.last_match(2).to_i)) ? "/#{Regexp.last_match(1)}/#{uuid}" : Regexp.last_match(0)
      end
      new_path = new_path&.gsub(/([?&])(#{QUERY_PARAMS.keys.join('|')})=(\d+)/) do
        (uuid = maps.dig(QUERY_PARAMS[Regexp.last_match(2)], Regexp.last_match(3).to_i)) ? "#{Regexp.last_match(1)}#{Regexp.last_match(2)}=#{uuid}" : Regexp.last_match(0)
      end
      new_dedup = dedup&.sub(/\A([a-z]+)-(\d+)(?=-|\z)/) do
        table = type&.safe_constantize&.table_name || Regexp.last_match(1).pluralize
        (uuid = maps.dig(table, (notifiable_id || Regexp.last_match(2)).to_i)) ? "#{Regexp.last_match(1)}-#{uuid}" : Regexp.last_match(0)
      end
      next if new_path == path && new_dedup == dedup

      execute "UPDATE notifications SET path = #{quote(new_path)}, dedup_key = #{quote(new_dedup)} WHERE id = #{id.to_i}"
    end
  end

  # Campos *_id do histórico ("role_id" => [1, 2]) passam a mostrar o novo id.
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
          next value unless value.is_a?(Integer)

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
      execute "UPDATE audit_logs SET changeset = #{quote(changeset.to_json)}::jsonb WHERE id = #{id.to_i}" if changed
    end
  end

  def quote(value)
    connection.quote(value)
  end
end
