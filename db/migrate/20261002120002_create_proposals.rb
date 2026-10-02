# Proposta comercial (RF 10). Código sequencial por ano (#P-2026-031).
# Aprovada, gera contrato e serviços contratados (RF 11).
class CreateProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :proposals do |t|
      t.integer :year, null: false
      t.integer :number, null: false
      t.string :title, null: false
      t.references :company, foreign_key: true
      t.references :lead, foreign_key: true
      t.references :opportunity, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.text :description
      t.string :payment_terms
      t.string :delivery_terms
      t.date :valid_until, null: false
      t.text :notes
      t.integer :total_cents, null: false, default: 0
      t.datetime :sent_at
      t.datetime :viewed_at
      t.date :decided_on
      t.string :rejection_reason
      t.text :rejection_details
      t.references :contract, foreign_key: true
      t.timestamps
    end
    add_index :proposals, [ :year, :number ], unique: true
    add_index :proposals, :status
    add_check_constraint :proposals, "company_id IS NOT NULL OR lead_id IS NOT NULL", name: "proposals_recipient_present"
  end
end
