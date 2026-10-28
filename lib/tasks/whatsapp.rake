namespace :whatsapp do
  # Fase 7a (docs/specs/whatsapp): liga as conversas que já existiam antes do vínculo automático ao
  # único lead em aberto ou contato com o mesmo telefone. Pode rodar mais de uma vez; as desvinculadas
  # à mão ficam de fora.
  desc "Vincula pelo telefone as conversas sem lead ou contato"
  task link_conversations: :environment do
    linked = WhatsappConversation.auto_linkable.where.not(wa_id: nil).find_each.count(&:auto_link!)
    puts "#{linked} conversa(s) vinculada(s) pelo telefone."
  end
end
