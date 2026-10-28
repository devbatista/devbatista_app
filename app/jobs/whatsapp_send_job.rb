# Envio de uma mensagem do Admin para a Meta (docs/specs/whatsapp, Fase 6), enfileirado pelo
# Whatsapp::Outbound. Texto (send_text), mídia (upload_media e send_media) ou template
# (send_template, com Whatsapp::TemplateComponents), citando a mensagem respondida.
#
# O wa_message_id é gravado logo depois da resposta da Meta; o status (enviada, entregue, lida)
# chega pelo webhook. Mensagem que já tem wa_message_id nunca é enviada de novo, para não chegar
# duplicada no celular do contato. Falha transitória tenta de novo com espera curta, mantendo
# "Enviando"; a definitiva fica na mensagem, em português.
#
# No POST da mensagem, só a falha em que o pedido não saiu (conexão, DNS) e o erro transitório
# da própria Meta tentam de novo. Sem confirmação da Meta (leitura que expirou, conexão
# interrompida: Whatsapp::Error#delivery_uncertain?), a mensagem falha sem nova tentativa, porque
# ela pode ter chegado ao contato. O upload da mídia não envia nada ao contato e tenta de novo.
class WhatsappSendJob < ApplicationJob
  RETRY_WAITS = [ 3, 10, 30, 60 ].freeze
  UNCERTAIN = "A Meta não confirmou o envio. Ele pode ter chegado ao contato: confira antes de tentar de novo.".freeze

  self.log_arguments = false
  queue_as :default
  discard_on ActiveJob::DeserializationError
  retry_on Whatsapp::Error, wait: ->(executions) { RETRY_WAITS.fetch(executions - 1, 60) }, attempts: 5 do |job, error|
    job.send(:fail!, job.arguments.first, error)
  end

  def perform(message)
    return if message.wa_message_id.present? || !message.status_pending?

    conversation = message.conversation
    return message.fail_send!(conversation.read_only_reason) unless conversation.sendable?

    sent = deliver(Whatsapp::Client.new(conversation.account), message, conversation)
    # Sem callbacks, para nada entre a resposta da Meta e a gravação do ID fazer o job falhar e repetir o envio.
    message.update_columns(wa_message_id: sent.wa_message_id, updated_at: Time.current)
    complete_recipient(conversation, sent)
    Rails.logger.info("[Whatsapp] mensagem enviada: message=#{message.id} wamid=#{sent.wa_message_id}")
  rescue Whatsapp::Error => e
    if @posting && e.delivery_uncertain?
      message.fail_send!(UNCERTAIN)
      return Rails.logger.warn("[Whatsapp] envio sem confirmação da Meta: message=#{message.id}, sem nova tentativa")
    end
    raise if e.transient?

    fail!(message, e)
  end

  private

  # O POST /messages: daqui em diante, falha de rede incerta não tem nova tentativa.
  def post
    @posting = true
    yield
  end

  def deliver(client, message, conversation)
    reply_to = message.reply_to_wa_message_id
    case message.kind
    when "text"
      post { client.send_text(conversation, message.body, reply_to: reply_to, preview_url: message.body.to_s.match?(%r{https?://})) }
    when "template"
      send_template(client, message, conversation, reply_to)
    else
      media_id = upload(client, message)
      post do
        client.send_media(conversation, type: message.kind, media_id: media_id, caption: message.body,
                                        filename: (message.media_filename if message.kind_document?), reply_to: reply_to)
      end
    end
  end

  def send_template(client, message, conversation, reply_to)
    template = conversation.account.templates.current.find_by(name: message.template_name, language: message.template_language)
    raise Whatsapp::Error, "O template #{message.template_name} não existe mais na conta." unless template

    fields = Whatsapp::TemplateFields.new(template)
    values = message.template_values
    header = values["header"].presence
    if (media = message.template_params.is_a?(Hash) && message.template_params["header_media"])
      header = { media => { id: upload(client, message), filename: (message.media_filename if media == "document") }.compact }
    end
    components = Whatsapp::TemplateComponents.build(body: fields.body_parameters(values["body"]), header: header,
                                                    url_buttons: values["buttons"].transform_keys(&:to_i))
    post { client.send_template(conversation, name: template.name, language: template.language, components: components, reply_to: reply_to) }
  end

  # O ID da mídia fica na mensagem: uma nova tentativa não sobe o arquivo de novo.
  def upload(client, message)
    return message.media_id if message.media_id.present?

    media_id = message.media.blob.open do |file|
      client.upload_media(file, filename: message.media_filename.presence || message.media.filename.to_s, mime_type: message.media.content_type)
    end
    message.update_columns(media_id: media_id)
    media_id
  end

  # A Meta devolve o telefone e o BSUID do destinatário: completa o que faltar na conversa.
  def complete_recipient(conversation, sent)
    attributes = { wa_id: (sent.wa_id if conversation.wa_id.nil?), bsuid: (sent.bsuid if conversation.bsuid.nil?) }.compact
    return if attributes.empty?

    conversation.update(attributes) || Rails.logger.info("[Whatsapp] conversa #{conversation.id} não completada: identificador já em outra conversa")
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[Whatsapp] conversa #{conversation.id} não completada: identificador já em outra conversa")
  end

  # Falha definitiva. Janela fechada (131047) fecha a janela na tela; BSUID recusado (131062)
  # sugere o template ou o telefone; token inválido (190) leva a conta a "Reconectar necessário".
  def fail!(message, error)
    conversation = message.conversation
    text = error.user_message
    case error.code
    when 131_047
      conversation.update!(last_inbound_at: Time.current - WhatsappConversation::WINDOW) if conversation.window_open?
    when 131_062
      text = "#{text} Envie um template ou use o telefone do contato, se ele compartilhar."
    when 190
      conversation.account.update!(status: "reconnect_required")
      conversation.broadcast_window_change
    end
    message.fail_send!(text, code: error.code)
    Rails.logger.warn("[Whatsapp] envio falhou: message=#{message.id} code=#{error.code}")
  end
end
