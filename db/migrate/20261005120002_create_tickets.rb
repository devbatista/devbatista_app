class CreateTickets < ActiveRecord::Migration[8.1]
  def up
    # Número sequencial gerado pelo banco (RF 21).
    execute "CREATE SEQUENCE ticket_numbers START WITH 1000"

    create_table :tickets do |t|
      t.integer :number, null: false, default: -> { "nextval('ticket_numbers')" }
      t.references :company, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.string :subject, null: false
      t.text :description, null: false
      t.string :category, null: false
      t.string :priority, null: false, default: "normal"
      t.string :status, null: false, default: "open"
      t.references :user, foreign_key: true
      t.datetime :opened_at, null: false
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :tickets, :number, unique: true
    add_index :tickets, :status
    add_index :tickets, :priority
  end

  def down
    drop_table :tickets
    execute "DROP SEQUENCE ticket_numbers"
  end
end
