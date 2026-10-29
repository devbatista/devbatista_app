# Fase 8 do WhatsApp (docs/specs/whatsapp): avisos.
# - A notificação ganha a prévia (body), para o aviso de mensagem recebida mostrar a última mensagem.
# - Um aviso não lido por conversa e usuário (Whatsapp::Notifier atualiza o que já existe).
class AddWhatsappNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :body, :string
    add_index :notifications, %i[user_id notifiable_id], unique: true, where: "kind = 'whatsapp_message' AND read_at IS NULL",
                                                         name: "index_notifications_whatsapp_unread"
  end
end
