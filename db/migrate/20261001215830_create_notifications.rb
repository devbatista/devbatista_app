# Central de notificações (RF 5). dedup_key evita repetir o mesmo alerta quando a
# rotina diária roda mais de uma vez.
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :level, null: false, default: "info"
      t.string :title, null: false
      t.string :area, null: false
      t.string :path
      t.string :notifiable_type
      t.bigint :notifiable_id
      t.string :dedup_key
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, [ :user_id, :read_at ]
    add_index :notifications, [ :user_id, :dedup_key ], unique: true, where: "dedup_key IS NOT NULL"
    add_index :notifications, [ :notifiable_type, :notifiable_id ]
  end
end
