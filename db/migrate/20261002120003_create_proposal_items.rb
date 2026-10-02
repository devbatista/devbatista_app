# Itens da proposta: serviços do catálogo com o valor proposto. O total da proposta
# é a soma dos itens.
class CreateProposalItems < ActiveRecord::Migration[8.1]
  def change
    create_table :proposal_items do |t|
      t.references :proposal, null: false, foreign_key: { on_delete: :cascade }
      t.references :service, null: false, foreign_key: true
      t.string :description
      t.string :recurrence, null: false, default: "monthly"
      t.integer :default_price_cents, null: false, default: 0
      t.integer :price_cents, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
