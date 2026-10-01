class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.string :legal_name, null: false
      t.string :trade_name, null: false
      t.string :cnpj, null: false
      t.string :status, null: false, default: "prospect"
      t.string :phone
      t.string :email
      t.string :website
      t.string :street
      t.string :city
      t.string :state, limit: 2
      t.string :zip_code
      t.text :notes
      t.date :customer_since
      t.string :external_id
      t.timestamps
    end
    add_index :companies, :cnpj, unique: true
    add_index :companies, :status
    add_index :companies, :trade_name
    add_index :companies, :external_id, unique: true, where: "external_id IS NOT NULL"

    add_foreign_key :activities, :companies
  end
end
