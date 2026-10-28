# Integração com o WhatsApp Business (Cloud API da Meta). Ver docs/specs/whatsapp.
module Whatsapp
  # Webhooks inscritos no app da Meta (WhatsApp → Configuração), na ordem da documentação.
  WEBHOOK_FIELDS = %w[messages smb_message_echoes history smb_app_state_sync account_update message_template_status_update
                      template_category_update phone_number_quality_update phone_number_name_update].freeze

  def self.config
    Rails.configuration.x.whatsapp
  end

  # Variáveis que faltam para conectar um número pelo Embedded Signup. Sem elas, a tela avisa e
  # desabilita o botão. As chaves de criptografia guardam o token.
  def self.missing_signup_configuration
    missing = { "META_APP_ID" => config.app_id, "META_APP_SECRET" => config.app_secret,
                "WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID" => config.embedded_signup_config_id }.select { |_name, value| value.blank? }.keys
    missing + ActiveRecordEncryptionCheck.missing_keys.map { |key| "ACTIVE_RECORD_ENCRYPTION_#{key.upcase}" }
  end
end
