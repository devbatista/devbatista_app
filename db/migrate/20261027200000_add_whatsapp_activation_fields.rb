# Conexão pelo Embedded Signup (Fase 4): validade do token, erro da ativação e registro do número
# sem coexistência. O número exibido só chega depois da conexão (phone_number_details), então a
# conta é salva antes, sem ele.
class AddWhatsappActivationFields < ActiveRecord::Migration[8.1]
  def change
    add_column :whatsapp_accounts, :token_expires_at, :datetime
    add_column :whatsapp_accounts, :activation_error, :string
    add_column :whatsapp_accounts, :registered_at, :datetime
    change_column_null :whatsapp_accounts, :display_phone_number, true
  end
end
