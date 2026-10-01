class CreateContracts < ActiveRecord::Migration[8.1]
  def up
    # Número interno sequencial gerado pelo banco (RF 17).
    execute "CREATE SEQUENCE contract_numbers START WITH 100"

    create_table :contracts do |t|
      t.integer :number, null: false, default: -> { "nextval('contract_numbers')" }
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.string :status, null: false, default: "draft"
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :renewal, null: false, default: "manual"
      t.integer :value_cents, null: false, default: 0
      t.string :periodicity, null: false, default: "monthly"
      t.text :notes
      t.timestamps
    end
    add_index :contracts, :number, unique: true
    add_index :contracts, :status
    add_index :contracts, :end_date
  end

  def down
    drop_table :contracts
    execute "DROP SEQUENCE contract_numbers"
  end
end
