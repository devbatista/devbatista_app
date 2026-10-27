# Monta os webhooks da Cloud API nos specs, no formato da documentação da Meta.
#
#   process_webhook(account, "messages", messages: [ wa_message("wamid.1", "Oi") ], contacts: [ wa_contact ])
module WhatsappWebhookHelpers
  CONTACT_PHONE = "5511991023344".freeze
  CONTACT_BSUID = "BR.118034776612".freeze
  BUSINESS_PHONE = "5511970702026".freeze # display_phone_number da factory

  # Uma mudança (changes[].value) de um campo que traz o número (metadata).
  def process_webhook(account, field, entry_id: account.waba_id, time: nil, **parts)
    value = { messaging_product: "whatsapp", metadata: { display_phone_number: BUSINESS_PHONE, phone_number_id: account.phone_number_id } }
    process_change(field, value.merge(parts), entry_id: entry_id, time: time)
  end

  # Uma mudança sem metadata (account_update, templates, número): entry.id é a WABA.
  def process_change(field, value, entry_id:, time: nil)
    Whatsapp::WebhookProcessor.new(entry_id: entry_id, field: field, value: value.deep_stringify_keys, time: time).call
  end

  def wa_contact(name: "Henrique Duarte", wa_id: CONTACT_PHONE, user_id: CONTACT_BSUID, username: nil)
    { profile: { name: name, username: username }.compact, wa_id: wa_id, user_id: user_id }.compact
  end

  def wa_message(id, body = nil, type: "text", from: CONTACT_PHONE, from_user_id: CONTACT_BSUID, at: Time.zone.parse("2026-10-27 10:00"), **extra)
    message = { from: from, from_user_id: from_user_id, id: id, timestamp: at.to_i.to_s, type: type }.compact
    message[type.to_sym] = { body: body } if type == "text"
    message.merge(extra)
  end

  def wa_status(id, status, at: Time.zone.parse("2026-10-27 10:05"), **extra)
    { id: id, status: status, timestamp: at.to_i.to_s, recipient_id: CONTACT_PHONE }.merge(extra)
  end
end

RSpec.configure { |config| config.include WhatsappWebhookHelpers }
