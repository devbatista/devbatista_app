# Templates (Fase 5). O template excluído fica no banco (as mensagens antigas apontam para ele
# por nome e idioma), mas o nome pode ser criado de novo na Meta depois de 30 dias: o índice único
# de nome e idioma passa a ignorar os excluídos. A conta guarda o andamento da sincronização.
class AddWhatsappTemplateManagement < ActiveRecord::Migration[8.1]
  def change
    remove_index :whatsapp_templates, %i[whatsapp_account_id name language], unique: true
    add_index :whatsapp_templates, %i[whatsapp_account_id name language], unique: true, where: "status <> 'deleted'",
                                                                           name: "index_whatsapp_templates_on_account_name_language"

    add_column :whatsapp_accounts, :templates_sync_requested_at, :datetime
    add_column :whatsapp_accounts, :templates_synced_at, :datetime
    add_column :whatsapp_accounts, :templates_sync_error, :string
  end
end
