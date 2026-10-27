# Campos que os webhooks da Fase 3 preenchem (docs/specs/whatsapp):
# - saved_name: nome do contato na agenda do app do celular (smb_app_state_sync, coexistência);
# - edited_at e revoked_at: mensagem editada ou apagada para todos (eco edit e revoke).
class AddWhatsappWebhookFields < ActiveRecord::Migration[8.1]
  def change
    add_column :whatsapp_conversations, :saved_name, :string
    add_column :whatsapp_messages, :edited_at, :datetime
    add_column :whatsapp_messages, :revoked_at, :datetime
  end
end
