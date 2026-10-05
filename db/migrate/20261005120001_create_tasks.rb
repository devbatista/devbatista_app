# Tarefa de um projeto (RF 19): status do quadro, prioridade, prazo e estimativa.
class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.references :user, foreign_key: true
      t.string :status, null: false, default: "backlog"
      t.string :priority, null: false, default: "normal"
      t.date :due_on
      t.integer :estimated_minutes
      t.date :completed_on
      t.timestamps
    end
    add_index :tasks, :status
    add_index :tasks, :due_on
  end
end
