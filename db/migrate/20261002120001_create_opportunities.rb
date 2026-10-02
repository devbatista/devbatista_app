# Oportunidade: negócio em andamento com um lead convertido ou um cliente (RF 9).
# Anda no pipeline de Reunião em diante.
class CreateOpportunities < ActiveRecord::Migration[8.1]
  def change
    create_table :opportunities do |t|
      t.string :title, null: false
      t.references :lead, foreign_key: true
      t.references :company, null: false, foreign_key: true
      t.references :service, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :stage, null: false, default: "meeting"
      t.integer :estimated_value_cents, null: false, default: 0
      t.integer :probability, null: false, default: 25
      t.date :expected_close_on
      t.text :notes
      t.string :next_step
      t.date :next_step_on
      t.string :lost_reason
      t.text :lost_details
      t.date :closed_on
      t.string :external_id
      t.timestamps
    end
    add_index :opportunities, :stage
    add_index :opportunities, :external_id, unique: true, where: "external_id IS NOT NULL"
    add_check_constraint :opportunities, "probability BETWEEN 0 AND 100", name: "opportunities_probability_range"
  end
end
