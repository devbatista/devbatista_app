module Whatsapp
  # Processa uma mudança (entry[].changes[]) do webhook da Cloud API, já fora da requisição
  # (WhatsappWebhookJob). Cada campo inscrito tem seu tratamento (docs/specs/whatsapp):
  #
  #   messages                        mensagens recebidas, avisos de sistema e status das enviadas
  #   smb_message_echoes              enviadas pelo app do celular (coexistência), edições e exclusões
  #   history                         histórico do celular em blocos (até 180 dias) e a mídia que chega depois
  #   smb_app_state_sync              agenda do celular: o nome salvo de cada contato
  #   account_update                  desconexão do número (PARTNER_REMOVED e outros) e reconexão
  #   message_template_status_update  aprovação, rejeição, pausa… dos templates
  #   template_category_update        categoria trocada pela Meta
  #   phone_number_quality_update,
  #   phone_number_name_update        relê qualidade, nome e limite do número na Graph API
  #
  # Idempotente: a Meta reenvia por até 7 dias, e mensagem que já entrou (wa_message_id) é
  # ignorada. Status de mensagem ainda não gravada (o webhook pode chegar antes de o envio
  # terminar de salvar) levanta StatusTargetMissing no fim, para o job tentar de novo.
  class WebhookProcessor
    class StatusTargetMissing < StandardError; end

    HANDLERS = {
      "messages" => :messages, "smb_message_echoes" => :echoes, "history" => :history, "smb_app_state_sync" => :state_sync,
      "account_update" => :account_update, "message_template_status_update" => :template_status,
      "template_category_update" => :template_category, "phone_number_quality_update" => :phone_number_update,
      "phone_number_name_update" => :phone_number_update
    }.freeze
    # Campos que trazem o número (metadata.phone_number_id); os outros trazem só a WABA (entry.id).
    NUMBER_FIELDS = %w[messages smb_message_echoes history smb_app_state_sync].freeze
    IGNORED_TYPES = %w[request_welcome].freeze

    DISCONNECT_EVENTS = %w[PARTNER_REMOVED PARTNER_APP_UNINSTALLED ACCOUNT_DELETED ACCOUNT_OFFBOARDED].freeze
    # Eventos de template sem status próprio no enum: voltam a aprovado ou só vão para o log.
    TEMPLATE_EVENT_STATUS = { "REINSTATED" => "APPROVED", "UNARCHIVED" => "APPROVED" }.freeze
    TEMPLATE_WARNINGS = %w[FLAGGED LOCKED].freeze

    STATUS_RANK = { "pending" => 0, "sent" => 1, "delivered" => 2, "read" => 3 }.freeze
    HISTORY_STATUS = { "PENDING" => "pending", "SENT" => "sent", "DELIVERED" => "delivered", "READ" => "read",
                       "PLAYED" => "read", "ERROR" => "failed" }.freeze

    def initialize(entry_id:, field:, value:, time: nil)
      @entry_id = entry_id.to_s
      @field = field.to_s
      @value = value || {}
      @time = time.present? ? Time.zone.at(time.to_i) : Time.current
      @missing_statuses = []
    end

    def call
      handler = HANDLERS[field]
      return log("campo #{field} ignorado") unless handler

      accounts = NUMBER_FIELDS.include?(field) ? number_accounts : waba_accounts
      return log("#{field} de uma conta que não está no Admin (#{account_reference})") if accounts.empty?

      accounts.each do |account|
        account.update_column(:last_webhook_at, Time.current)
        send(handler, account)
      end
      raise StatusTargetMissing, "status de mensagem ainda não gravada: #{@missing_statuses.join(", ")}" if @missing_statuses.any?
    end

    private

    attr_reader :field, :value, :time

    def number_accounts
      WhatsappAccount.where(phone_number_id: value.dig("metadata", "phone_number_id").to_s).to_a
    end

    def waba_accounts
      WhatsappAccount.where(waba_id: value.dig("waba_info", "waba_id").presence || @entry_id).to_a
    end

    def account_reference
      NUMBER_FIELDS.include?(field) ? "phone_number_id #{value.dig("metadata", "phone_number_id")}" : "WABA #{@entry_id}"
    end

    # ---------- messages ----------

    def messages(account)
      contacts = Array(value["contacts"])
      Array(value["messages"]).each do |message|
        next if IGNORED_TYPES.include?(message["type"]) || edit_or_revoke(account, message) || recorded?(message)

        message["type"] == "system" ? system_message(account, message) : inbound(account, message, contact_for(contacts, message))
      end
      Array(value["statuses"]).each { |status| status(account, status) }
      Array(value["errors"]).each { |error| log("erro #{error["code"]} no número #{account.phone_number_id}: #{error["title"]}") }
    end

    # O bloco contacts descreve o remetente: nome do perfil, @usuário, telefone e BSUID.
    def contact_for(contacts, message)
      contacts.find do |contact|
        (contact["wa_id"].present? && contact["wa_id"] == message["from"]) ||
          (contact["user_id"].present? && contact["user_id"] == message["from_user_id"])
      end || (contacts.one? ? contacts.first : {})
    end

    def inbound(account, message, contact)
      bsuid = message["from_user_id"].presence || contact["user_id"]
      wa_id = message["from"].presence || contact["wa_id"]
      return log("mensagem #{message["id"]} sem remetente ignorada") if bsuid.blank? && wa_id.blank?

      conversation = WhatsappConversation.locate!(
        account, bsuid: bsuid, wa_id: wa_id, parent_bsuid: message["from_parent_user_id"].presence || contact["parent_user_id"],
                 profile_name: contact.dig("profile", "name"), username: contact.dig("profile", "username")
      )
      record(conversation, message, direction: "inbound", origin: "contact", status: "received")
    end

    # Troca de BSUID (user_changed_user_id) ou de número (user_changed_number): a conversa antiga
    # fica com o identificador novo, e o aviso entra na linha do tempo.
    def system_message(account, message)
      system = message["system"] || {}
      changed_number = system["type"] == "user_changed_number"
      bsuid = system["user_id"]
      wa_id = changed_number ? system["wa_id"] : nil
      return log("aviso de sistema #{message["id"]} sem identificação ignorado") if bsuid.blank? && wa_id.blank?

      conversation = WhatsappConversation.locate!(
        account, bsuid: bsuid, wa_id: wa_id, parent_bsuid: system["parent_user_id"],
                 previous_bsuid: system["previous_user_id"], previous_wa_id: (message["from"] if changed_number)
      )
      record(conversation, message, direction: "inbound", origin: "contact", status: "received")
    end

    def status(account, data)
      message = account_message(account, data["id"])
      return @missing_statuses << data["id"] unless message

      at = MessageAttributes.timestamp(data["timestamp"])
      case data["status"]
      when "sent" then promote(message, "sent")
      when "delivered" then promote(message, "delivered", delivered_at: at)
      when "read", "played" then promote(message, "read", delivered_at: at, read_at: at)
      when "failed" then mark_failed(message, data)
      else log("status #{data["status"]} ignorado")
      end
      complete_bsuid(account, message.conversation, data["recipient_user_id"])
    end

    # O status só avança (enviada → entregue → lida), mesmo que os webhooks cheguem fora de ordem.
    # A leitura e a gravação acontecem com a mensagem travada (with_lock relê a linha), para dois
    # status processados ao mesmo tempo não se sobrescreverem.
    def promote(message, status, **times)
      message.with_lock do
        next if message.status_failed?

        attributes = times.select { |name, _| message[name].nil? }
        attributes[:status] = status if STATUS_RANK.fetch(message.status, 0) < STATUS_RANK.fetch(status)
        message.update!(attributes) if attributes.any?
      end
    end

    def mark_failed(message, data)
      message.with_lock do
        next if message.status_delivered? || message.status_read?

        error = Array(data["errors"]).first || {}
        code = error["code"]
        text = Error::MESSAGES.fetch(code) { error.dig("error_data", "details").presence || error["title"] }
        message.update!(status: "failed", error_code: code&.to_s, error_message: text)
      end
    end

    # Conversa iniciada pelo telefone ganha o BSUID quando o status traz recipient_user_id.
    def complete_bsuid(account, conversation, bsuid)
      return if bsuid.blank? || conversation.bsuid.present? || conversation.wa_id.blank?

      WhatsappConversation.locate!(account, bsuid: bsuid, wa_id: conversation.wa_id)
    end

    # ---------- smb_message_echoes ----------

    def echoes(account)
      Array(value["message_echoes"]).each do |message|
        next if edit_or_revoke(account, message) || recorded?(message)

        bsuid = message["to_user_id"]
        wa_id = message["to"]
        next log("eco #{message["id"]} sem destinatário ignorado") if bsuid.blank? && wa_id.blank?

        conversation = WhatsappConversation.locate!(account, bsuid: bsuid, wa_id: wa_id)
        record(conversation, message, direction: "outbound", origin: "phone", status: "sent")
      end
    end

    # Edição e exclusão para todos: mudam a mensagem original, sem criar outra.
    def edit_or_revoke(account, message)
      type = message["type"]
      return false unless %w[edit revoke].include?(type)

      content = message[type] || {}
      original = account_message(account, content["original_message_id"])
      at = MessageAttributes.timestamp(message["timestamp"])
      if original.nil?
        log("#{type} de mensagem que não está no Admin ignorado")
      elsif type == "revoke"
        original.update!(revoked_at: at) unless original.revoked_at
      elsif original.edited_at.nil? || original.edited_at < at
        edited = MessageAttributes.call(content["message"].to_h.merge("timestamp" => message["timestamp"]))
        replace_content(original, edited.merge(edited_at: at))
      end
      true
    end

    # ---------- history ----------

    def history(account)
      business = digits(value.dig("metadata", "display_phone_number")) || digits(account.display_phone_number)
      Array(value["history"]).each do |chunk|
        if (error = Array(chunk["errors"]).first)
          account.update!(history_sync_error: error.dig("error_data", "details").presence || error["title"])
          next
        end
        Array(chunk["threads"]).each do |thread|
          Array(thread["messages"]).each { |message| history_message(account, message, thread["id"], business) }
        end
        history_progress(account, chunk.dig("metadata", "progress"))
      end
      # Mídia das mensagens que vieram como media_placeholder, num webhook separado.
      Array(value["messages"]).each { |message| history_media(account, message, business) }
    end

    # Mensagem do histórico: não abre a janela nem conta como não lida.
    def history_message(account, message, person, business)
      return if recorded?(message) || person.blank?

      outbound = digits(message["from"]) == business
      conversation = WhatsappConversation.locate!(account, **identity(person))
      status = outbound ? HISTORY_STATUS.fetch(message.dig("history_context", "status").to_s, "sent") : "received"
      record(conversation, message, from_history: true, direction: outbound ? "outbound" : "inbound",
                                    origin: outbound ? "phone" : "contact", status: status)
    end

    def history_media(account, message, business)
      original = account_message(account, message["id"])
      if original
        replace_content(original, MessageAttributes.call(message))
      elsif digits(message["from"]) != business
        history_message(account, message, message["from"], business)
      end
    end

    # A Meta numera os blocos e informa o progresso (100 = terminou); eles podem chegar fora de ordem.
    def history_progress(account, progress)
      return if progress.nil?

      attributes = { history_sync_progress: [ account.history_sync_progress.to_i, progress.to_i ].max }
      attributes[:history_synced_at] = Time.current if progress.to_i >= 100 && account.history_synced_at.nil?
      account.update!(attributes)
    end

    # O id da conversa no histórico é o telefone; um BSUID ("BR.…") também é aceito.
    def identity(person)
      person.to_s.match?(/\A[A-Z]{2}\./) ? { bsuid: person } : { wa_id: person }
    end

    # ---------- smb_app_state_sync ----------

    # Cria a conversa (ainda sem mensagem) para o nome salvo não se perder até a pessoa escrever.
    def state_sync(account)
      Array(value["state_sync"]).each do |item|
        contact = item["contact"] || {}
        next unless item["type"] == "contact" && contact["phone_number"].present?

        if item["action"] == "remove"
          account.conversations.find_by(wa_id: digits(contact["phone_number"]))&.update!(saved_name: nil)
        else
          WhatsappConversation.locate!(account, wa_id: contact["phone_number"], saved_name: contact["full_name"].presence || contact["first_name"])
        end
      end
      account.update!(contacts_synced_at: Time.current) if account.contacts_synced_at.nil?
    end

    # ---------- account_update ----------

    # Desconexão pelo celular (coexistência), pelo cliente ou pela Meta: as conversas ficam e o
    # Admin para de enviar. Os outros eventos (violação, restrição, banimento) vão para o log.
    def account_update(account)
      event = value["event"].to_s
      phone = digits(value["phone_number"])
      return if phone && phone != digits(account.display_phone_number)

      if DISCONNECT_EVENTS.include?(event)
        reason = [ event, value.dig("disconnection_info", "reason") ].compact.join(": ")
        account.update!(status: "disconnected", disconnected_at: time, disconnect_reason: reason) unless account.disconnected?
      elsif event == "ACCOUNT_RECONNECTED" && account.disconnected? && account.disconnect_reason.to_s.start_with?("ACCOUNT_OFFBOARDED")
        account.update!(status: "connected", disconnected_at: nil, disconnect_reason: nil)
      else
        details = value.slice("violation_info", "restriction_info", "ban_info").presence
        Rails.logger.warn("[Whatsapp] account_update #{event} na WABA #{account.waba_id}#{" #{details.to_json}" if details}")
      end
    end

    # ---------- templates ----------

    def template_status(account)
      template = find_template(account)
      return log("status de template que não está no Admin: #{value["message_template_name"]}") unless template

      event = value["event"].to_s
      return Rails.logger.warn("[Whatsapp] template #{template.name}: #{event}") if TEMPLATE_WARNINGS.include?(event)

      data = { "name" => template.name, "status" => TEMPLATE_EVENT_STATUS.fetch(event, event), "category" => value["message_template_category"] }
      reasons = [ value["reason"], value.dig("rejection_info", "reason") ].compact_blank - [ "NONE" ]
      template.update!(WhatsappTemplate.attributes_from_meta(data, current: template).slice(:status, :category)
                         .merge(rejection_reason: reasons.join(" — ").presence, last_synced_at: Time.current))
    end

    # Só a troca concluída (previous_category) muda o template; o aviso de troca futura vai para o log.
    def template_category(account)
      template = find_template(account)
      return unless template
      return log("template #{template.name} vai mudar para #{value["correct_category"]}") if value["previous_category"].blank?

      data = { "name" => template.name, "category" => value["new_category"] }
      template.update!(category: WhatsappTemplate.attributes_from_meta(data, current: template)[:category])
    end

    # O webhook manda o idioma com hífen (en-US); a Graph API e o banco usam sublinhado (en_US).
    def find_template(account)
      account.templates.find_by(meta_template_id: value["message_template_id"].to_s) ||
        account.templates.find_by(name: value["message_template_name"], language: value["message_template_language"].to_s.tr("-", "_"))
    end

    # ---------- phone_number_quality_update, phone_number_name_update ----------

    def phone_number_update(account)
      phone = digits(value["display_phone_number"])
      return if phone && phone != digits(account.display_phone_number)

      attributes = { messaging_limit_tier: value["max_daily_conversations_per_business"].presence || value["current_limit"].presence }.compact
      begin
        attributes.merge!(WhatsappAccount.attributes_from_phone_details(Client.new(account).phone_number_details))
      rescue Whatsapp::Error => e
        log("não foi possível reler o número #{account.phone_number_id}: #{e.message}")
      end
      account.update!(attributes) if attributes.any?
    end

    # ---------- gravação ----------

    def record(conversation, message, from_history: false, **attributes)
      data = MessageAttributes.call(message).merge(attributes, from_history: from_history)
      return replace_reaction(conversation, data) if data[:kind] == "reaction"

      created = conversation.messages.create!(data)
      conversation.record_message!(created)
      WhatsappMediaJob.perform_later(created) if created.media_id.present?
      ActiveRecord.after_all_transactions_commit { Notifier.message_received(created) } if created.inbound? && !from_history
      created
    rescue ActiveRecord::RecordNotUnique
      nil # outro job gravou a mesma mensagem
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors.of_kind?(:wa_message_id, :taken)
    end

    # A reação mais nova da pessoa sobre uma mensagem substitui as anteriores. Emoji vazio
    # (reação removida) também é gravado, para um reenvio atrasado da reação antiga não voltar.
    def replace_reaction(conversation, data)
      previous = conversation.messages.kind_reaction.where(direction: data[:direction], reaction_to_wa_message_id: data[:reaction_to_wa_message_id])
      return if previous.where("sent_at > ?", data[:sent_at]).exists?

      previous.destroy_all
      conversation.messages.create!(data)
    end

    # Novo conteúdo de uma mensagem (edição ou mídia do histórico). Mídia nova é baixada de novo.
    def replace_content(message, attributes)
      message.assign_attributes(attributes.slice(:kind, :body, :media_id, :media_mime_type, :media_filename, :edited_at))
      new_media = message.media_id_changed? && message.media_id.present?
      message.save!
      message.media.purge if new_media && message.media.attached?
      WhatsappMediaJob.perform_later(message) if new_media
      conversation = message.conversation
      conversation.update!(preview: message.preview_text) if conversation.last_message_at == message.sent_at
    end

    def recorded?(message)
      message["id"].present? && WhatsappMessage.exists?(wa_message_id: message["id"])
    end

    def account_message(account, wa_message_id)
      return if wa_message_id.blank?

      WhatsappMessage.joins(:conversation).find_by(wa_message_id: wa_message_id, whatsapp_conversations: { whatsapp_account_id: account.id })
    end

    def digits(value)
      value.to_s.gsub(/\D/, "").presence
    end

    # Só identificadores e códigos: nada de conteúdo de mensagem ou dado pessoal.
    def log(text)
      Rails.logger.info("[Whatsapp] #{text}")
      nil
    end
  end
end
