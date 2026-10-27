# WhatsApp Business (Cloud API da Meta): contas conectadas, conversas, mensagens e templates
# (docs/specs/whatsapp). O contato do WhatsApp é identificado pelo BSUID (business-scoped user ID),
# guardado em `bsuid`, e não em `user_id`, que nesta base é sempre o usuário dono do registro.
class CreateWhatsappTables < ActiveRecord::Migration[8.1]
  def change
    create_table :whatsapp_accounts, id: :uuid do |t|
      t.string :business_id
      t.string :waba_id, null: false
      t.string :phone_number_id, null: false
      t.string :display_phone_number, null: false
      t.string :verified_name
      t.text :access_token # criptografado (Active Record Encryption)
      t.string :status, null: false, default: "pending"
      t.boolean :coexistence, null: false, default: false
      t.string :quality_rating, null: false, default: "unknown"
      t.string :messaging_limit_tier
      t.references :connected_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :connected_at
      t.datetime :subscribed_at
      t.datetime :disconnected_at
      t.string :disconnect_reason
      t.string :contacts_sync_request_id
      t.datetime :contacts_synced_at
      t.string :history_sync_request_id
      t.integer :history_sync_progress
      t.datetime :history_synced_at
      t.string :history_sync_error
      t.datetime :last_webhook_at
      t.timestamps
    end
    add_index :whatsapp_accounts, :phone_number_id, unique: true
    add_index :whatsapp_accounts, :waba_id

    create_table :whatsapp_conversations, id: :uuid do |t|
      t.references :whatsapp_account, type: :uuid, null: false, foreign_key: true
      t.string :bsuid
      t.string :parent_bsuid
      t.string :wa_id
      t.string :username
      t.string :profile_name
      t.references :lead, type: :uuid, foreign_key: true
      t.references :contact, type: :uuid, foreign_key: true
      t.datetime :last_inbound_at
      t.datetime :last_message_at
      t.integer :unread_count, null: false, default: 0
      t.string :preview
      t.timestamps
      t.check_constraint "bsuid IS NOT NULL OR wa_id IS NOT NULL", name: "whatsapp_conversations_identified"
      t.check_constraint "lead_id IS NULL OR contact_id IS NULL", name: "whatsapp_conversations_single_link"
    end
    add_index :whatsapp_conversations, %i[whatsapp_account_id bsuid], unique: true, where: "bsuid IS NOT NULL"
    add_index :whatsapp_conversations, %i[whatsapp_account_id wa_id], unique: true, where: "wa_id IS NOT NULL"
    add_index :whatsapp_conversations, %i[whatsapp_account_id last_message_at]

    create_table :whatsapp_messages, id: :uuid do |t|
      t.references :whatsapp_conversation, type: :uuid, null: false, foreign_key: true
      t.string :direction, null: false
      t.string :kind, null: false, default: "text"
      t.string :origin, null: false
      t.text :body
      t.string :wa_message_id
      t.string :status, null: false
      t.string :error_code
      t.text :error_message
      t.string :template_name
      t.string :template_language
      t.jsonb :template_params, null: false, default: []
      t.string :media_id
      t.string :media_mime_type
      t.string :media_filename
      t.string :reply_to_wa_message_id # mensagem citada na resposta (context.id)
      t.string :reaction_to_wa_message_id # mensagem que recebeu a reação
      t.string :reaction_emoji # vazio quando a pessoa remove a reação
      t.references :user, type: :uuid, foreign_key: true # autor (mensagens enviadas pelo Admin)
      t.boolean :from_history, null: false, default: false
      t.datetime :sent_at, null: false
      t.datetime :delivered_at
      t.datetime :read_at
      t.jsonb :raw_payload, null: false, default: {}
      t.timestamps
    end
    add_index :whatsapp_messages, :wa_message_id, unique: true, where: "wa_message_id IS NOT NULL"
    add_index :whatsapp_messages, %i[whatsapp_conversation_id sent_at]
    add_index :whatsapp_messages, :reply_to_wa_message_id
    add_index :whatsapp_messages, :reaction_to_wa_message_id

    create_table :whatsapp_templates, id: :uuid do |t|
      t.references :whatsapp_account, type: :uuid, null: false, foreign_key: true
      t.string :meta_template_id
      t.string :name, null: false
      t.string :language, null: false
      t.string :category, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :components, null: false, default: []
      t.integer :variables_count, null: false, default: 0
      t.string :rejection_reason
      t.datetime :last_synced_at
      t.timestamps
    end
    add_index :whatsapp_templates, %i[whatsapp_account_id name language], unique: true
    add_index :whatsapp_templates, :meta_template_id, unique: true, where: "meta_template_id IS NOT NULL"
  end
end
