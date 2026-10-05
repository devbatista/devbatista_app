# Despesa e conta a pagar são o mesmo registro (RF 24 e 26). Centro de custo é uma área
# interna ou um cliente; em moeda estrangeira guarda o valor original, a moeda e o valor em
# reais na data do pagamento (até lá, estimado pelo câmbio do dia).
class CreatePayables < ActiveRecord::Migration[8.1]
  def change
    create_table :payables do |t|
      t.references :supplier, null: false, foreign_key: true
      t.references :recurring_expense, foreign_key: true
      t.references :company, foreign_key: true
      t.string :cost_center
      t.string :description, null: false
      t.string :category, null: false
      t.string :currency, null: false, default: "BRL"
      t.integer :original_amount_cents
      t.decimal :exchange_rate, precision: 12, scale: 6
      t.integer :amount_cents, null: false
      t.date :competence, null: false
      t.date :due_on, null: false
      t.date :paid_on
      t.string :status, null: false, default: "pending"
      t.text :notes
      t.timestamps
    end
    add_index :payables, :status
    add_index :payables, :competence
    add_index :payables, :due_on
    add_index :payables, [ :recurring_expense_id, :competence ], unique: true, where: "recurring_expense_id IS NOT NULL",
                                                                  name: "index_payables_once_per_competence"
    add_check_constraint :payables, "company_id IS NOT NULL OR cost_center IS NOT NULL", name: "payables_cost_center_present"
    add_check_constraint :payables, "amount_cents >= 0", name: "payables_amount_positive"
  end
end
