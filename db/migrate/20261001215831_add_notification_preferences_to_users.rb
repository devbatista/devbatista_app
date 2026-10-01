# Por tipo de alerta, se o usuário também quer receber por e-mail.
class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_preferences, :jsonb, null: false, default: {}
  end
end
