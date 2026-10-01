# Serviço contratado: cliente + serviço do catálogo + condições (RF 16). Origem do MRR.
class CreateCustomerServices < ActiveRecord::Migration[8.1]
  def change
    create_table :customer_services do |t|
      t.references :company, null: false, foreign_key: true
      t.references :service, null: false, foreign_key: true
      t.references :contract, foreign_key: true
      t.integer :price_cents, null: false
      t.string :recurrence, null: false, default: "monthly"
      t.integer :mrr_cents, null: false, default: 0
      t.date :start_date, null: false
      t.integer :due_day
      t.string :status, null: false, default: "active"
      t.date :ended_on
      t.string :description
      t.text :notes
      t.timestamps
    end
    add_index :customer_services, :status
  end
end
