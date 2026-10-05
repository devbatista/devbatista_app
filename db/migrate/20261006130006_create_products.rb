# Produto próprio da DevBatista (RF 35). MRR e clientes vêm das assinaturas; o custo mensal é
# registrado mês a mês (ProductCost) para a série dos indicadores.
class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.string :url
      t.text :description
      t.string :status, null: false, default: "idea"
      t.text :notes
      t.timestamps
    end
    add_index :products, :name, unique: true

    create_table :product_costs do |t|
      t.references :product, null: false, foreign_key: true
      t.date :month, null: false
      t.integer :amount_cents, null: false, default: 0
      t.timestamps
    end
    add_index :product_costs, [ :product_id, :month ], unique: true
  end
end
