# Fornecedor (RF 36): quem a DevBatista paga, com as mesmas categorias das despesas.
class CreateSuppliers < ActiveRecord::Migration[8.1]
  def change
    create_table :suppliers do |t|
      t.string :name, null: false
      t.string :category, null: false
      t.string :contact_name
      t.string :phone
      t.string :email
      t.string :website
      t.text :notes
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :suppliers, :name, unique: true
  end
end
