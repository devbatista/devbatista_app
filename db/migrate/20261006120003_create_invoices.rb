# Nota fiscal emitida fora do sistema (RF 28): número, competência, valor e PDF, XML ou link.
class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :company, null: false, foreign_key: true
      t.string :number
      t.date :competence, null: false
      t.integer :amount_cents, null: false
      t.date :issued_on
      t.string :status, null: false, default: "pending"
      t.string :description
      t.string :url
      t.text :notes
      t.timestamps
    end
    add_index :invoices, :number, unique: true, where: "number IS NOT NULL"
    add_index :invoices, :competence
  end
end
