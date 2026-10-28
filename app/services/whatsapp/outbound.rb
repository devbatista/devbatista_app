module Whatsapp
  # Envio pelo Admin (docs/specs/whatsapp, Fase 6). Confere a conta e a janela de 24h no servidor
  # (o campo de envio também bloqueia, mas não basta), grava a mensagem de saída (Enviando, origem
  # Admin, autor) e enfileira o WhatsappSendJob, que fala com a Meta.
  #
  #   result = Whatsapp::Outbound.new(conversation, user: current_user).deliver(kind: "text", body: "Bom dia!")
  #   result.error   # => nil, ou o motivo em português
  #
  # Texto e mídia só com a janela aberta; template sempre.
  class Outbound
    Result = Data.define(:message, :error)

    def initialize(conversation, user:)
      @conversation = conversation
      @user = user
    end

    # kind: "text" (body e, opcional, file), "template" (template_id, values: { body:, header:, buttons: }, header_file).
    # reply_to: wa_message_id da mensagem citada.
    def deliver(kind:, body: nil, file: nil, reply_to: nil, template_id: nil, values: {}, header_file: nil)
      return failure(@conversation.read_only_reason) unless @conversation.sendable?

      attributes = kind == "template" ? template_attributes(template_id, values, header_file) : free_attributes(body.to_s.strip, file)
      return failure(attributes) if attributes.is_a?(String)

      attributes[:reply_to_wa_message_id] = reply_to if reply_to.present? && @conversation.messages.exists?(wa_message_id: reply_to)
      record(attributes)
    end

    # "Tentar de novo": a mensagem que falhou vai de novo como mensagem nova; a antiga fica.
    def retry(message)
      return failure("Só mensagens enviadas pelo Admin que falharam podem ser enviadas de novo.") unless message.retryable?
      return failure(@conversation.read_only_reason) unless @conversation.sendable?
      return failure(Error::MESSAGES.fetch(131_047)) if !message.kind_template? && !@conversation.window_open?

      record(message.slice(:kind, :body, :reply_to_wa_message_id, :template_name, :template_language, :template_params,
                           :media_mime_type, :media_filename).symbolize_keys.merge(media: message.media.attached? ? message.media.blob : nil).compact)
    end

    private

    def free_attributes(body, file)
      return Error::MESSAGES.fetch(131_047) unless @conversation.window_open?
      return "Escreva a mensagem ou anexe um arquivo." if body.empty? && file.blank?
      return "A mensagem tem até #{WhatsappMessage::TEXT_LIMIT} caracteres." if body.length > WhatsappMessage::TEXT_LIMIT
      return { kind: "text", body: body } if file.blank?

      kind = WhatsappMessage.upload_kind(file.content_type)
      return "O WhatsApp não aceita esse tipo de arquivo (#{file.content_type.presence || 'desconhecido'})." unless kind

      limit = Client::MEDIA_LIMITS.fetch(kind)
      if file.size > limit
        return "O arquivo tem #{size(file.size)} e passa do limite de #{size(limit)} para #{Client::MEDIA_LABELS.fetch(kind)}."
      end

      { kind: kind, body: (body.presence if Client::CAPTION_TYPES.include?(kind)), media: file,
        media_mime_type: file.content_type, media_filename: file.original_filename.to_s.truncate(200) }
    end

    def template_attributes(template_id, values, header_file)
      template = @conversation.account.templates.status_approved.find_by(id: template_id)
      return "Escolha um template aprovado desta conta." unless template

      spec = TemplateFields.new(template)
      values = values.to_h.with_indifferent_access
      body = Array(values[:body]).map { |value| value.to_s.strip }.first(spec.body_count)
      header = Array(values[:header]).map { |value| value.to_s.strip }.first(spec.header_count)
      buttons = spec.url_button_indexes.to_h { |index| [ index.to_s, values.dig(:buttons, index.to_s).to_s.strip ] }
      missing = body.count(&:blank?) + (spec.body_count - body.size) + header.count(&:blank?) + (spec.header_count - header.size) + buttons.values.count(&:blank?)
      return "Preencha todas as variáveis do template." if missing.positive?

      params = { "body" => body, "header" => header, "buttons" => buttons }
      attributes = { kind: "template", template_name: template.name, template_language: template.language, body: spec.fill(body) }
      return attributes.merge(template_params: params) unless spec.header_media

      return "Este template pede #{Client::MEDIA_LABELS.fetch(spec.header_media)} no cabeçalho. Anexe o arquivo." if header_file.blank?
      return "O cabeçalho do template pede #{Client::MEDIA_LABELS.fetch(spec.header_media)}." unless WhatsappMessage.upload_kind(header_file.content_type) == spec.header_media
      if header_file.size > Client::MEDIA_LIMITS.fetch(spec.header_media)
        return "O arquivo passa do limite de #{size(Client::MEDIA_LIMITS.fetch(spec.header_media))} para #{Client::MEDIA_LABELS.fetch(spec.header_media)}."
      end

      attributes.merge(template_params: params.merge("header_media" => spec.header_media), media: header_file,
                       media_mime_type: header_file.content_type, media_filename: header_file.original_filename.to_s.truncate(200))
    end

    def record(attributes)
      message = nil
      WhatsappMessage.transaction do
        message = @conversation.messages.create!(attributes.merge(direction: "outbound", origin: "admin", status: "pending",
                                                                  user: @user, sent_at: Time.current))
        @conversation.record_message!(message)
      end
      WhatsappSendJob.perform_later(message)
      Result.new(message: message, error: nil)
    end

    def failure(error)
      Result.new(message: nil, error: error)
    end

    def size(bytes)
      ActiveSupport::NumberHelper.number_to_human_size(bytes)
    end
  end
end
