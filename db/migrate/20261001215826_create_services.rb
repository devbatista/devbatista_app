# Catálogo de serviços (RF 15).
class CreateServices < ActiveRecord::Migration[8.1]
  def change
    create_table :services do |t|
      t.string :name, null: false
      t.text :description
      t.string :category, null: false
      t.string :kind, null: false
      t.integer :default_price_cents, null: false, default: 0
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :services, :name, unique: true
  end
end
