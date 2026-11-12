# Próximo passo com data e hora (lista "Próximos passos" do Comercial). Os registros que já tinham
# data ficam com o mesmo dia às 09:00 de Brasília, gravado em UTC como os outros timestamps.
class ChangeNextStepOnToDatetime < ActiveRecord::Migration[8.1]
  TABLES = %i[leads opportunities].freeze

  def up
    TABLES.each do |table|
      execute <<~SQL.squish
        ALTER TABLE #{table} ALTER COLUMN next_step_on TYPE timestamp(6) without time zone
        USING ((next_step_on + time '09:00') AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'UTC'
      SQL
      add_index table, :next_step_on
    end
  end

  def down
    TABLES.each do |table|
      remove_index table, :next_step_on
      execute <<~SQL.squish
        ALTER TABLE #{table} ALTER COLUMN next_step_on TYPE date
        USING ((next_step_on AT TIME ZONE 'UTC') AT TIME ZONE 'America/Sao_Paulo')::date
      SQL
    end
  end
end
