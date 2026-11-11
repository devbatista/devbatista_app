# Mensagens do WhatsApp nas respostas das tools (ver_conversa_whatsapp, as "Conversa do dia" do
# ver_lead e o filtro de respostas do buscar_leads): o texto como a pessoa leu, com a mídia marcada
# entre colchetes ("[áudio]", "[imagem] legenda"), para o Claude ler a conversa sem baixar nada.
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
        return unavailable_text(message) if message.kind_unsupported? && message.error_code.present?

        tag = message.kind_template? ? "template #{message.template_name}" : MEDIA_LABELS.fetch(message.kind, message.kind_label.downcase)
        tag = "#{tag}: #{message.media_filename}" if message.kind_document? && message.media_filename.present?
        [ "[#{tag}]", message.body.to_s.strip.presence ].compact.join(" ")
      end

      def message_data(message)
        {
          direcao: message.inbound? ? "recebida" : "enviada", horario: message.sent_at.iso8601, tipo: message.kind,
          texto: message_text(message), origem: message.origin_label.downcase,
          enviada_por: message.user&.name, status: (message.status_label if message.outbound?),
          erro: (message.error_message if message.status_failed? || message.error_code.present?), editada: (true if message.edited_at),
          do_historico: (true if message.from_history?), wamid: message.wa_message_id
        }.compact
      end

      # A Meta avisou que não repassa o conteúdo à Cloud API (131060: mensagem indisponível, comum na
      # coexistência com aparelho vinculado não suportado; 131051: tipo não suportado). O texto não
      # existe do lado do Admin: só no app do WhatsApp Business.
      def unavailable_text(message)
        "[mensagem indisponível: a Meta não enviou o conteúdo à API (código #{message.error_code}). Leia no app do WhatsApp Business]"
      end

      def whatsapp_readable?
        Pundit.policy!(user, WhatsappConversation).index?
      end

      # Conversas ligadas ao lead (como o card da ficha), da mais recente para a mais antiga.
      def lead_conversations(lead)
        policy_scope(WhatsappConversation).with_messages.where(lead: lead).includes(:account).order(last_message_at: :desc).to_a
      end

      # A janela vale pela conversa que recebeu por último (é por ela que enviar_whatsapp responde).
      def whatsapp_window(conversations)
        latest = conversations.select(&:last_inbound_at).max_by(&:last_inbound_at)
        { janela_aberta: latest&.window_open? || false, janela_fecha_em: (latest.window_closes_at.iso8601 if latest&.window_open?),
          ultima_recebida_em: latest&.last_inbound_at&.iso8601 }
      end

      # As `limit` mensagens mais recentes do escopo, da mais antiga para a mais nova, e o total.
      def latest_messages(scope, limit)
        [ scope.includes(:user).reorder(sent_at: :desc, id: :desc).limit(limit).to_a.reverse, scope.count ]
      end

      # Mensagens dos dias das interações "Conversa do dia" (Interaction#automatic?, uma por conversa e
      # dia), por id da interação: as `limit` mais recentes entre todos os dias, e quantas do dia ficaram
      # de fora. Sem leitura na área WhatsApp, nada.
      def daily_conversation_messages(interactions, limit)
        daily = interactions.select(&:automatic?)
        return {} if daily.empty? || !whatsapp_readable?

        scope = daily.map { |day| WhatsappMessage.timeline.where(whatsapp_conversation_id: day.whatsapp_conversation_id,
                                                                 sent_at: day.occurred_on.in_time_zone.all_day) }.reduce(:or)
        scope = scope.where(conversation: policy_scope(WhatsappConversation))
        messages, = latest_messages(scope, limit)
        shown = messages.group_by { |message| [ message.whatsapp_conversation_id, message.sent_at.to_date ] }
        totals = scope.pluck(:whatsapp_conversation_id, :sent_at).map { |id, at| [ id, at.in_time_zone.to_date ] }.tally

        daily.to_h do |day|
          key = [ day.whatsapp_conversation_id, day.occurred_on ]
          list = shown.fetch(key, [])
          omitted = totals.fetch(key, 0) - list.size
          [ day.id, { mensagens: list.map { |message| message_data(message) }, mensagens_omitidas: (omitted if omitted.positive?) }.compact ]
        end
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
