# Aplicação (RF 29): sistema, site ou app de um cliente. Na spec é "Application"; no código é
# App para não colidir com ApplicationRecord/ApplicationPolicy. A hospedagem aponta para um
# servidor ou um serviço externo (polimórfica).
class CreateApps < ActiveRecord::Migration[8.1]
  def change
    create_table :apps do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :environment, null: false, default: "production"
      t.string :status, null: false, default: "active"
      t.string :url
      t.string :tech_stack
      t.string :repository_url
      t.string :hosting_type
      t.bigint :hosting_id
      t.references :project, foreign_key: true
      t.references :contract, foreign_key: true
      t.references :user, foreign_key: true
      t.string :vault_reference
      t.timestamps
    end
    add_index :apps, [ :hosting_type, :hosting_id ]
    add_index :apps, :status
  end
end
