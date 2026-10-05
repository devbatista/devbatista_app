# Projeto de um cliente (RF 18): previsão, orçamento e progresso (manual ou pelas tarefas).
class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "planning"
      t.date :start_date
      t.date :due_date, null: false
      t.date :closed_on
      t.integer :budget_cents, null: false, default: 0
      t.integer :progress, null: false, default: 0
      t.boolean :progress_from_tasks, null: false, default: true
      t.references :contract, foreign_key: true
      t.references :proposal, foreign_key: true
      t.timestamps
    end
    add_index :projects, :status
    add_index :projects, :due_date
    add_check_constraint :projects, "progress BETWEEN 0 AND 100", name: "projects_progress_range"
  end
end
