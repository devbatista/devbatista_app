# Stream do sino e dos avisos do navegador de cada usuário ([usuário, :notifications]). Além do nome
# assinado (Turbo::StreamsChannel), confere que o stream é o do próprio usuário conectado.
#
#   <%= turbo_stream_from current_user, :notifications, channel: NotificationsChannel %>
class NotificationsChannel < Turbo::StreamsChannel
  def subscribed
    # Mesmo formato do Turbo::Streams::StreamName para [usuário, :notifications].
    return reject unless verified_stream_name_from_params == "#{current_user.to_gid_param}:notifications"

    super
  end
end
