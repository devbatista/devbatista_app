# Repositório de arquivos (RF 37). O vínculo é polimórfico (cliente, contrato, projeto,
# proposta ou fornecedor); company_id guarda o cliente para a Visão 360º.
class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :title, null: false
      t.string :kind, null: false
      t.string :documentable_type
      t.bigint :documentable_id
      t.references :company, foreign_key: true
      t.references :uploaded_by, null: false, foreign_key: { to_table: :users }
      t.text :notes
      t.timestamps
    end
    add_index :documents, [ :documentable_type, :documentable_id ]
  end
end
