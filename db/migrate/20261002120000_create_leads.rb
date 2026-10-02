# Lead: contato com potencial de negócio, antes de virar cliente (RF 6).
# Percorre Novo Lead → Contato Realizado → Qualificado; na conversão vira empresa,
# contato e oportunidade (RF 8).
class CreateLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :leads do |t|
      t.string :name, null: false
      t.string :company_name
      t.string :phone
      t.string :whatsapp
      t.string :email
      t.string :origin, null: false
      t.references :service, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "new"
      t.date :entered_on, null: false
      t.text :notes
      t.string :next_step
      t.date :next_step_on
      t.string :lost_reason
      t.text :lost_details
      t.datetime :lost_at
      t.references :company, foreign_key: true
      t.datetime :converted_at
      t.string :external_id
      t.timestamps
    end
    add_index :leads, :status
    add_index :leads, :external_id, unique: true, where: "external_id IS NOT NULL"
  end
end
