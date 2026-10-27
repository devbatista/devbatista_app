# Integração com o WhatsApp Business (Cloud API da Meta). Ver docs/specs/whatsapp.
module Whatsapp
  def self.config
    Rails.configuration.x.whatsapp
  end
end
