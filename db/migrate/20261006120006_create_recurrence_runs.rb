# Execuções da rotina de recorrências: o que foi gerado, vencido e cancelado em cada uma.
class CreateRecurrenceRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :recurrence_runs do |t|
      t.references :user, foreign_key: true
      t.date :run_on, null: false
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :generated_count, null: false, default: 0
      t.integer :overdue_count, null: false, default: 0
      t.integer :cancelled_count, null: false, default: 0
      t.date :horizon_on
      t.text :warnings
      t.timestamps
    end
  end
end
