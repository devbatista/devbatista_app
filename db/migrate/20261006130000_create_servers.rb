# Servidor (RF 30): inventário com fornecedor, IP ou hostname, ambiente, SO e custo mensal.
# Sem senha nem chave SSH: só a referência ao item no cofre de senhas.
class CreateServers < ActiveRecord::Migration[8.1]
  def change
    create_table :servers do |t|
      t.references :company, null: false, foreign_key: true
      t.references :supplier, null: false, foreign_key: true
      t.string :name, null: false
      t.string :host, null: false
      t.string :environment, null: false, default: "production"
      t.string :os
      t.string :instance_type
      t.integer :monthly_cost_cents, null: false, default: 0
      t.string :vault_reference
      t.text :notes
      t.timestamps
    end
    add_index :servers, :name, unique: true
  end
end
