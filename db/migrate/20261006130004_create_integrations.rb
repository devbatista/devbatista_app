# Integração de uma aplicação com plataforma ou API externa (RF 33). Sem chaves nem tokens.
class CreateIntegrations < ActiveRecord::Migration[8.1]
  def change
    create_table :integrations do |t|
      t.references :app, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :variant
      t.string :environment, null: false, default: "production"
      t.string :status, null: false, default: "configuring"
      t.string :purpose, null: false
      t.text :notes
      t.timestamps
    end
  end
end
