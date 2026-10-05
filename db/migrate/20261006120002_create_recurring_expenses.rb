# Regra de despesa recorrente (RF 27): gera os títulos a pagar dos próximos períodos.
class CreateRecurringExpenses < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_expenses do |t|
      t.references :supplier, null: false, foreign_key: true
      t.string :description, null: false
      t.string :category, null: false
      t.references :company, foreign_key: true
      t.string :cost_center
      t.string :currency, null: false, default: "BRL"
      t.integer :amount_cents, null: false
      t.string :periodicity, null: false, default: "monthly"
      t.integer :due_day, null: false
      t.date :start_on, null: false
      t.string :status, null: false, default: "active"
      t.date :ended_on
      t.text :notes
      t.timestamps
    end
    add_check_constraint :recurring_expenses, "company_id IS NOT NULL OR cost_center IS NOT NULL", name: "recurring_expenses_cost_center_present"
  end
end
