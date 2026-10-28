# Lead ou contato com WhatsApp ou telefone novo: liga as conversas sem vínculo com esse número (com
# e sem o nono dígito), pela mesma regra da conversa nova (WhatsappConversation#auto_link!). As
# desvinculadas à mão ficam de fora (WhatsappConversation.auto_linkable).
class WhatsappAutoLinkJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(record)
    wa_ids = [ record.whatsapp, record.phone ].flat_map { |number| Whatsapp::Phone.wa_ids(number) }.uniq
    WhatsappConversation.auto_linkable.where(wa_id: wa_ids).find_each(&:auto_link!) if wa_ids.any?
  end
end
