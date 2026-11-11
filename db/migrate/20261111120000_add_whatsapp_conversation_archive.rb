# Conversa arquivada (docs/specs/whatsapp, "Arquivar conversa"): sai da caixa de entrada sem apagar
# nada e volta sozinha quando chega mensagem nova. Quando e quem arquivou.
class AddWhatsappConversationArchive < ActiveRecord::Migration[8.1]
  def change
    add_column :whatsapp_conversations, :archived_at, :datetime
    add_reference :whatsapp_conversations, :archived_by, type: :uuid, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
