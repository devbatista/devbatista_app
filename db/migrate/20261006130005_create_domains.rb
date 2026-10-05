# Domínio (RF 31): registrador, vencimento, renovação automática e custo. Alertas a 60, 30 e
# 7 dias (Configurações); sem renovação automática tem destaque na lista.
class CreateDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :domains do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :registrar, null: false
      t.date :registered_on
      t.date :expires_on, null: false
      t.boolean :auto_renew, null: false, default: false
      t.string :currency, null: false, default: "BRL"
      t.integer :renewal_cost_cents, null: false, default: 0
      t.string :paid_by, null: false, default: "client"
      t.string :dns_provider
      t.text :notes
      t.timestamps
    end
    add_index :domains, :name, unique: true
    add_index :domains, :expires_on
  end
end
