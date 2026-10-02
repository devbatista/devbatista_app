# Interações registradas à mão com o lead ou na oportunidade (ligação, WhatsApp, e-mail...).
class CreateInteractions < ActiveRecord::Migration[8.1]
  def change
    create_table :interactions do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.date :occurred_on, null: false
      t.text :notes, null: false
      t.timestamps
    end
    add_index :interactions, [ :subject_type, :subject_id ]
  end
end
