# Fase 7a do WhatsApp (docs/specs/whatsapp): vínculo da conversa com o CRM.
# - Telefone e WhatsApp do lead e do contato só com os dígitos (colunas geradas), para achar o
#   cadastro da conversa pelo número (Whatsapp::Phone.stored_forms).
# - Quem vinculou e quando (sem quem: vínculo automático pelo telefone), e a marca de que a conversa
#   foi desvinculada à mão (o vínculo automático não a liga de novo até o telefone mudar).
# - A interação "WhatsApp" do dia aponta a conversa que a gerou: uma por conversa, cadastro e dia.
class AddWhatsappCrmLink < ActiveRecord::Migration[8.1]
  def change
    %i[leads contacts].each do |table|
      %i[whatsapp phone].each do |column|
        add_column table, :"#{column}_digits", :virtual, type: :string, stored: true,
                                                         as: "NULLIF(regexp_replace(#{column}, '\\D', '', 'g'), '')"
        add_index table, :"#{column}_digits"
      end
    end

    add_column :whatsapp_conversations, :linked_at, :datetime
    add_column :whatsapp_conversations, :auto_link_blocked_at, :datetime
    add_reference :whatsapp_conversations, :linked_by, type: :uuid, index: false, foreign_key: { to_table: :users, on_delete: :nullify }

    add_reference :interactions, :whatsapp_conversation, type: :uuid, index: false, foreign_key: { on_delete: :nullify }
    add_index :interactions, %i[whatsapp_conversation_id subject_type subject_id occurred_on], unique: true,
                                                                                               where: "whatsapp_conversation_id IS NOT NULL",
                                                                                               name: "index_interactions_whatsapp_daily"
  end
end
