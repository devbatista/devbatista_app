module Whatsapp
  # Converte uma mensagem dos webhooks (messages, smb_message_echoes, history) nos atributos de
  # WhatsappMessage: tipo, texto, mídia, mensagem citada e reação. Direção, origem e status ficam
  # com quem grava (Whatsapp::WebhookProcessor), que sabe de onde a mensagem veio.
  #
  #   MessageAttributes.call("id" => "wamid...", "timestamp" => "1749416383", "type" => "text", "text" => { "body" => "Oi" })
  #   # => { wa_message_id: "wamid...", kind: "text", body: "Oi", sent_at: ..., ... }
  #
  # Tipo que o Admin não mostra (pedido, enquete, placeholder de mídia do histórico…) vira
  # "unsupported", com o payload guardado em raw_payload.
  module MessageAttributes
    MEDIA = %w[image audio video document sticker].freeze
    KINDS = (MEDIA + %w[text location contacts interactive button reaction system]).freeze

    def self.call(message)
      type = message["type"].to_s
      content = message[type].is_a?(Hash) ? message[type] : {}
      attributes = {
        wa_message_id: message["id"], kind: KINDS.include?(type) ? type : "unsupported",
        sent_at: timestamp(message["timestamp"]), reply_to_wa_message_id: message.dig("context", "id"),
        raw_payload: message, body: body(type, content, message)
      }
      attributes.merge!(media_id: content["id"], media_mime_type: content["mime_type"], media_filename: content["filename"]) if MEDIA.include?(type)
      attributes.merge!(reaction_to_wa_message_id: content["message_id"], reaction_emoji: content["emoji"].to_s) if type == "reaction"
      if (error = Array(message["errors"]).first)
        attributes.merge!(error_code: error["code"].to_s, error_message: error.dig("error_data", "details").presence || error["title"])
      end
      attributes
    end

    def self.timestamp(value)
      value.present? ? Time.zone.at(value.to_i) : Time.current
    end

    def self.body(type, content, message)
      case type
      when "text", "system" then content["body"]
      when *MEDIA then content["caption"]
      when "button" then content["text"]
      when "interactive"
        reply = content["button_reply"] || content["list_reply"] || {}
        reply["title"]
      when "location"
        coordinates = "#{content["latitude"]}, #{content["longitude"]}" if content["latitude"]
        [ content["name"], content["address"], coordinates ].compact_blank.join(" · ")
      when "contacts"
        Array(message["contacts"]).map { |card| shared_contact(card) }.join("\n")
      end.presence
    end

    # "Barbara J. Johnson (+1 (415) 555-0829)"
    def self.shared_contact(card)
      phones = Array(card["phones"]).filter_map { |phone| phone["phone"] || phone["wa_id"] }
      [ card.dig("name", "formatted_name"), ("(#{phones.join(", ")})" if phones.any?) ].compact.join(" ")
    end
    private_class_method :body, :shared_contact
  end
end
