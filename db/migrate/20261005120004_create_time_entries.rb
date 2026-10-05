# Horas trabalhadas (RF 20): cliente e duração obrigatórios; projeto, tarefa e chamado opcionais.
class CreateTimeEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :time_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :project, foreign_key: true
      t.references :task, foreign_key: true
      t.references :ticket, foreign_key: true
      t.date :worked_on, null: false
      t.integer :minutes, null: false
      t.text :description
      t.timestamps
    end
    add_index :time_entries, :worked_on
    add_check_constraint :time_entries, "minutes > 0", name: "time_entries_minutes_positive"
  end
end
