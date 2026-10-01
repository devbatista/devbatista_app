# Histórico de negócio: o que aconteceu com cada registro, em linguagem de gente.
# Alimenta a aba Atividades da Visão 360º e o feed do dashboard.
class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities do |t|
      t.references :user, foreign_key: true
      t.references :company # chave estrangeira criada em CreateCompanies
      t.string :subject_type
      t.bigint :subject_id
      t.string :area, null: false
      t.string :action, null: false
      t.string :description, null: false
      t.datetime :created_at, null: false
    end
    add_index :activities, [ :subject_type, :subject_id ]
    add_index :activities, :created_at
  end
end
