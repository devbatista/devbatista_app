# Mensagens do WhatsApp nas respostas das tools (ver_conversa_whatsapp e o filtro de respostas do
# buscar_leads): o texto como a pessoa leu, com a mídia marcada entre colchetes ("[áudio]",
# "[imagem] legenda"), para o Claude ler a conversa sem baixar nada.
module Mcp
  module Tools
    module WhatsappData
      MEDIA_LABELS = {
        "image" => "imagem", "audio" => "áudio", "video" => "vídeo", "document" => "documento", "sticker" => "figurinha",
        "location" => "localização", "contacts" => "contato", "system" => "aviso do sistema", "unsupported" => "mensagem não suportada"
      }.freeze
      # Respostas a botão e lista: o texto do botão é o que a pessoa escolheu.
      PLAIN_KINDS = %w[text interactive button].freeze
      # Mensagem que conta como resposta do contato (reação e aviso do sistema não).
      REPLY_KINDS_EXCLUDED = %w[reaction system].freeze

      private

      def message_text(message)
        return "[mensagem apagada]" if message.revoked_at
        return message.body.to_s if PLAIN_KINDS.include?(message.kind)

        tag = message.kind_template? ? "template #{message.template_name}" : MEDIA_LABELS.fetch(message.kind, message.kind_label.downcase)
        tag = "#{tag}: #{message.media_filename}" if message.kind_document? && message.media_filename.present?
        [ "[#{tag}]", message.body.to_s.strip.presence ].compact.join(" ")
      end

      def message_data(message)
        {
          direcao: message.inbound? ? "recebida" : "enviada", horario: message.sent_at.iso8601, tipo: message.kind,
          texto: message_text(message), origem: message.origin_label.downcase,
          enviada_por: message.user&.name, status: (message.status_label if message.outbound?),
          erro: (message.error_message if message.status_failed?), editada: (true if message.edited_at),
          do_historico: (true if message.from_history?), wamid: message.wa_message_id
        }.compact
      end

      # Mensagens que o contato mandou a partir do dia (início do dia, no fuso do sistema).
      def replies_since(day)
        WhatsappMessage.inbound.where.not(kind: REPLY_KINDS_EXCLUDED).where(sent_at: day.in_time_zone.beginning_of_day..)
      end

      def parse_day(value, field)
        Date.iso8601(value.to_s)
      rescue Date::Error
        fail!("Data inválida em #{field}: use AAAA-MM-DD, como #{Date.current.iso8601}.")
      end
    end
  end
end
