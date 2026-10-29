module Whatsapp
  # Avisos de mensagem recebida na central de notificações (docs/specs/whatsapp, Fase 8): um por
  # conversa e usuário, nunca um por mensagem.
  # - Mensagem recebida (fora do histórico, sem reação nem aviso do sistema): cria o aviso da conversa
  #   para quem pode ver a área, ou atualiza o não lido que já existe ("Nome · N mensagens novas",
  #   a prévia da última e a data, que o leva ao topo da lista).
  # - Abrir a conversa ou responder pelo celular (não lidas zeradas) marca os avisos dela como lidos,
  #   para todos.
  # - Cada aviso criado ou atualizado vai também para o navegador de quem o recebeu (o partial
  #   notifications/whatsapp_alert, no stream do usuário), com o nome e a prévia, como na lista.
  #
  # Chamado depois do commit pelo processamento do webhook; os broadcasts levam só referências.
  class Notifier
    KIND = "whatsapp_message".freeze

    def self.message_received(message)
      new.message_received(message)
    end

    def self.conversation_read(conversation)
      new.conversation_read(conversation)
    end

    def message_received(message)
      return unless notify?(message)

      conversation = message.conversation
      conversation.with_lock do
        next if conversation.unread_count.zero? # alguém já abriu a conversa

        title = "#{conversation.display_name} · #{count_label(conversation.unread_count)}"
        recipients.each { |user| upsert(user, conversation, message, title) }
      end
    end

    def conversation_read(conversation)
      unread = Notification.unread.where(kind: KIND, notifiable: conversation)
      users = User.where(id: unread.select(:user_id)).to_a
      return if users.empty?

      unread.update_all(read_at: Time.current, updated_at: Time.current)
      users.each { |user| Notification.refresh_bell(user) }
    end

    private

    def notify?(message)
      message.inbound? && !message.from_history? && !message.kind_reaction? && !message.kind_system?
    end

    def recipients
      User.active.includes(:role).select { |user| Notification.receives?(KIND, user) }
    end

    def upsert(user, conversation, message, title)
      notification = Notification.unread.find_by(user: user, kind: KIND, notifiable: conversation)
      if notification
        notification.update!(title: title, body: message.preview_text, created_at: Time.current)
      else
        notification = Notification.create!(user: user, kind: KIND, title: title, body: message.preview_text, notifiable: conversation,
                                            path: Rails.application.routes.url_helpers.whatsapp_conversation_path(conversation),
                                            level: "info", area: Notification::KINDS.dig(KIND, :area))
        notification.email_later
      end
      Turbo::StreamsChannel.broadcast_append_later_to([ user, :notifications ], target: "whatsapp_alerts", partial: "notifications/whatsapp_alert",
                                                                                 locals: { notification: notification, message_id: message.id })
    end

    def count_label(count)
      count = [ count, 1 ].max
      count == 1 ? "1 mensagem nova" : "#{count} mensagens novas"
    end
  end
end
