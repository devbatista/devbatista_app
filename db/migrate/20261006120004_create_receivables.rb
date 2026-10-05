# Receita e título a receber são o mesmo registro (RF 23 e 25). Os recorrentes nascem dos
# serviços contratados ativos, uma única vez por competência (RF 27).
class CreateReceivables < ActiveRecord::Migration[8.1]
  def change
    create_table :receivables do |t|
      t.references :company, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :customer_service, foreign_key: true
      t.references :service, foreign_key: true
      t.references :contract, foreign_key: true
      t.references :invoice, foreign_key: true
      t.string :description, null: false
      t.string :category, null: false
      t.integer :amount_cents, null: false
      t.date :competence, null: false
      t.date :due_on, null: false
      t.date :paid_on
      t.integer :paid_amount_cents
      t.string :status, null: false, default: "pending"
      t.text :notes
      t.timestamps
    end
    add_index :receivables, :status
    add_index :receivables, :competence
    add_index :receivables, :due_on
    add_index :receivables, [ :customer_service_id, :competence ], unique: true, where: "customer_service_id IS NOT NULL",
                                                                   name: "index_receivables_once_per_competence"
    add_check_constraint :receivables, "amount_cents >= 0", name: "receivables_amount_positive"
  end
end
