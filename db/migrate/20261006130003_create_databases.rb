# Banco de dados de uma aplicação (RF 32): tecnologia, versão, ambiente, provedor e backup.
# Usuário, senha e string de conexão ficam no cofre; aqui só a referência.
class CreateDatabases < ActiveRecord::Migration[8.1]
  def change
    create_table :databases do |t|
      t.references :app, null: false, foreign_key: true
      t.string :technology, null: false
      t.string :version
      t.string :environment, null: false, default: "production"
      t.string :provider
      t.string :backup_policy
      t.string :vault_reference
      t.text :notes
      t.timestamps
    end
  end
end
