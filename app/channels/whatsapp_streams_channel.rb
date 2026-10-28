# Turbo Streams do WhatsApp (caixa de entrada, conversa e contador do menu). Além do nome assinado
# do stream (Turbo::StreamsChannel), exige que a pessoa possa ver a área WhatsApp.
#
#   <%= turbo_stream_from conversation, channel: WhatsappStreamsChannel %>
class WhatsappStreamsChannel < Turbo::StreamsChannel
  def subscribed
    return reject unless WhatsappConversationPolicy.new(current_user, WhatsappConversation).index?

    super
  end
end
