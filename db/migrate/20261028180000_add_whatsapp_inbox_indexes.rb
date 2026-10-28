# Conversas (Fase 6): índices da caixa de entrada e da linha do tempo.
# - lista por conta, da última mensagem para trás, com o id para desempatar o cursor;
# - não lidas (filtro e contador do menu) e janela aberta (filtro);
# - linha do tempo paginada por cursor (sent_at, id), que substitui o índice só por sent_at.
class AddWhatsappInboxIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :whatsapp_conversations, %i[whatsapp_account_id last_message_at]
    add_index :whatsapp_conversations, %i[whatsapp_account_id last_message_at id], order: { last_message_at: :desc, id: :desc },
                                                                                   where: "last_message_at IS NOT NULL", name: "index_whatsapp_conversations_inbox"
    add_index :whatsapp_conversations, :whatsapp_account_id, where: "unread_count > 0 AND last_message_at IS NOT NULL",
                                                             name: "index_whatsapp_conversations_unread"
    add_index :whatsapp_conversations, %i[whatsapp_account_id last_inbound_at], name: "index_whatsapp_conversations_window"

    remove_index :whatsapp_messages, %i[whatsapp_conversation_id sent_at]
    add_index :whatsapp_messages, %i[whatsapp_conversation_id sent_at id], name: "index_whatsapp_messages_timeline"
  end
end
