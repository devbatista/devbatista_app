class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :position
      t.string :phone
      t.string :whatsapp
      t.string :email
      t.boolean :primary, null: false, default: false
      t.text :notes
      t.string :external_id
      t.timestamps
    end
    # Um único contato principal por empresa, garantido também no banco.
    add_index :contacts, :company_id, unique: true, where: "\"primary\"", name: "index_contacts_one_primary_per_company"
    add_index :contacts, :external_id, unique: true, where: "external_id IS NOT NULL"
  end
end
