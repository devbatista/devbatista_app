# Histórico do atendimento: resposta ao cliente, nota interna ou mensagem do cliente
# registrada pela equipe (no MVP o cliente não acessa o sistema).
class CreateTicketMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_messages do |t|
      t.references :ticket, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false, default: "reply"
      t.references :contact, foreign_key: true
      t.string :channel
      t.text :body, null: false
      t.timestamps
    end
  end
end
