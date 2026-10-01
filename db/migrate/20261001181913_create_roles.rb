class CreateRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.string :name, null: false
      t.string :key, null: false
      t.jsonb :permissions, null: false, default: {}

      t.timestamps
    end
    add_index :roles, :key, unique: true
  end
end
