# Baixa a mídia de uma mensagem do WhatsApp para o Active Storage (S3 em produção). O ID que
# chega pelo webhook vale 7 dias, então o download acontece logo que a mensagem entra.
#
# Falha transitória (rede, limite, erro da Meta) tenta de novo; a definitiva (mídia expirada,
# acima do limite, token revogado) fica no log e a mensagem segue sem o arquivo.
class WhatsappMediaJob < ApplicationJob
  EXTENSIONS = {
    "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp", "audio/ogg" => ".ogg", "audio/mpeg" => ".mp3",
    "audio/mp4" => ".m4a", "audio/aac" => ".aac", "audio/amr" => ".amr", "video/mp4" => ".mp4", "video/3gpp" => ".3gp"
  }.freeze

  queue_as :default

  discard_on ActiveJob::DeserializationError
  retry_on Whatsapp::Error, wait: :polynomially_longer, attempts: 6 do |job, error|
    Rails.logger.warn("[Whatsapp] mídia da mensagem #{job.arguments.first.id} não baixada: #{error.message}")
  end

  def perform(message)
    return if message.media_id.blank? || message.media.attached?

    media = Whatsapp::Client.new(message.conversation.account).download_media(message.media_id)
    message.media.attach(io: media.file, filename: filename(message, media.mime_type), content_type: media.mime_type)
    message.broadcast_message_later # o "baixando…" da conversa aberta vira a mídia
  rescue Whatsapp::Error => e
    raise if e.transient?

    Rails.logger.warn("[Whatsapp] mídia da mensagem #{message.id} não baixada: #{e.message}")
  ensure
    media&.file&.close!
  end

  private

  # Documento vem com nome; foto, áudio e vídeo, não: o nome sai do ID da mídia e do tipo.
  def filename(message, mime_type)
    return message.media_filename if message.media_filename.present?

    mime = mime_type.to_s.split(";").first.to_s.strip
    "whatsapp-#{message.media_id}#{EXTENSIONS.fetch(mime) { Rack::Mime::MIME_TYPES.key(mime) }}"
  end
end
