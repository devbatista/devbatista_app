# Assinatura de um produto próprio (RF 35), registrada à mão no MVP.
class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :product, null: false, foreign_key: true
      t.references :company, foreign_key: true
      t.string :subscriber_name, null: false
      t.string :email
      t.string :plan, null: false
      t.integer :monthly_value_cents, null: false, default: 0
      t.date :started_on, null: false
      t.date :trial_ends_on
      t.date :cancelled_on
      t.string :status, null: false, default: "active"
      t.text :notes
      t.timestamps
    end
    add_index :subscriptions, :status
  end
end
