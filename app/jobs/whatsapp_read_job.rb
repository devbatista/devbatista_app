# Marca como lida na Meta a última mensagem recebida da conversa (os ticks azuis aparecem para o
# contato), quando alguém abre a conversa no Admin ou recebe mensagem com ela aberta. Uma vez por
# mensagem: o read_at da mensagem recebida guarda quando o Admin leu, gravado só nas que ainda
# estão sem ele, depois da resposta da Meta. A conversa não fica travada durante a chamada.
class WhatsappReadJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError
  retry_on Whatsapp::Error, wait: :polynomially_longer, attempts: 3

  def perform(conversation)
    return unless conversation.sendable?

    unread = conversation.messages.inbound.where(from_history: false, read_at: nil).where.not(wa_message_id: nil)
    last = unread.where.not(kind: %w[reaction system]).reorder(sent_at: :desc, id: :desc).first
    return unless last

    Whatsapp::Client.new(conversation.account).mark_as_read(last.wa_message_id)
    unread.where(sent_at: ..last.sent_at).update_all(read_at: Time.current)
  rescue Whatsapp::Error => e
    raise if e.transient?

    Rails.logger.warn("[Whatsapp] leitura não marcada na conversa #{conversation.id}: code=#{e.code} fbtrace_id=#{e.fbtrace_id}")
  end
end
