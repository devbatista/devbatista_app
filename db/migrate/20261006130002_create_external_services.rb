# Serviço externo (RF 34): SaaS ou infraestrutura de terceiros usado por um cliente, com custo
# na moeda original, periodicidade e quem paga. Só os pagos pela DevBatista entram no custo
# direto do cliente.
class CreateExternalServices < ActiveRecord::Migration[8.1]
  def change
    create_table :external_services do |t|
      t.string :name, null: false
      t.string :plan
      t.references :supplier, null: false, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :app, foreign_key: true
      t.string :currency, null: false, default: "BRL"
      t.integer :cost_cents, null: false, default: 0
      t.string :periodicity, null: false, default: "monthly"
      t.string :paid_by, null: false, default: "devbatista"
      t.boolean :active, null: false, default: true
      t.string :vault_reference
      t.text :notes
      t.timestamps
    end
  end
end
