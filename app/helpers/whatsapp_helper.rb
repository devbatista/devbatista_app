# Tela de integração do WhatsApp (Tecnologia → Integrações → WhatsApp, docs/specs/whatsapp).
module WhatsappHelper
  ACCOUNT_TONES = { "pending" => "info", "registration_pending" => "warn", "connected" => "good",
                    "reconnect_required" => "crit", "disconnected" => "mute" }.freeze
  QUALITY_TONES = { "green" => "good", "yellow" => "warn", "red" => "crit", "unknown" => "mute" }.freeze

  def whatsapp_account_badge(account)
    tag.span(account.status_label, class: "badge b-#{ACCOUNT_TONES[account.status]} dot-l")
  end

  def whatsapp_quality_badge(account)
    status_badge(account.quality_rating_label, QUALITY_TONES[account.quality_rating])
  end

  # Linha do tempo da conexão, em [rótulo, estado (:done, :cur ou :todo), detalhe].
  def whatsapp_steps(account)
    steps = [ [ "Autorizado na Meta", :done, whatsapp_time(account.connected_at) ],
              [ "App inscrito na conta", account.subscribed_at ? :done : :cur, whatsapp_time(account.subscribed_at) || "em andamento" ] ]
    steps.concat(account.coexistence? ? whatsapp_sync_steps(account) : [ whatsapp_registration_step(account) ])
    receiving = account.last_webhook_at ? "último evento #{whatsapp_time(account.last_webhook_at)}" : "aguardando o primeiro evento"
    steps << [ "Recebendo mensagens", account.connected? ? :cur : :todo, (receiving if account.connected?) ]
  end

  # Algo em andamento que muda sozinho (ativação ou histórico): a lista se atualiza. O histórico
  # conta só no primeiro dia da conexão, para a tela não ficar recarregando se ele não vier.
  def whatsapp_busy?(account)
    return false if account.activation_error? || !account.status.in?(%w[pending connected])
    return true if account.pending?

    account.coexistence? && account.history_sync_request_id? && account.history_synced_at.nil? && !account.history_sync_error? &&
      account.connected_at.present? && account.connected_at > 1.day.ago
  end

  def whatsapp_messaging_limit(account)
    return "—" if account.messaging_limit_tier.blank?

    limit = account.messaging_limit_label
    limit.match?(/\A[\d.]+\z/) ? "#{limit} contatos novos em 24h" : limit
  end

  def whatsapp_initials(account)
    account.verified_name.to_s.split.first(2).map { |word| word[0] }.join.upcase.presence || "WA"
  end

  # ---------- Templates ----------

  TEMPLATE_TONES = { "approved" => "good", "pending" => "warn", "rejected" => "crit", "disabled" => "crit", "in_appeal" => "warn" }.freeze
  BUTTON_ICONS = { "url" => "↗ ", "phone" => "☎ " }.freeze

  def whatsapp_template_badge(template)
    status_badge(template.status_label, TEMPLATE_TONES.fetch(template.status, "mute"))
  end

  # Linha da lista: o motivo da rejeição, a explicação do status ou o início do corpo.
  def whatsapp_template_note(template)
    return "Motivo da Meta: #{template.rejection_label}." if template.status_rejected? && template.rejection_reason.present?

    template.status_note || template.body_text.truncate(110)
  end

  def whatsapp_account_label(account)
    [ account.verified_name.presence, account.display_phone_number.presence ].compact.join(" · ").presence || account.phone_number_id
  end

  # Texto da prévia, com os exemplos no lugar das variáveis ({{1}} → <mark>Beatriz</mark>).
  # O texto é escapado antes; só o <mark> (com o exemplo escapado pelo tag) entra como HTML.
  def whatsapp_preview_text(text, examples)
    html = ERB::Util.html_escape(text.to_s).to_str.gsub(/\{\{\s*(\d+)\s*\}\}/) do
      number = Regexp.last_match(1).to_i
      tag.mark(examples[number - 1].presence || "{{#{number}}}").to_str
    end
    html.html_safe
  end

  def whatsapp_button_label(button)
    "#{BUTTON_ICONS[button["type"]]}#{button["text"].presence || 'Botão'}"
  end

  # ---------- Conversas ----------

  MESSAGE_STATUS = { "pending" => [ "", :clock, "Enviando" ], "sent" => [ "", :check, "Enviada" ], "delivered" => [ "", :dbl, "Entregue" ],
                     "read" => [ " read", :dbl, "Lida" ], "failed" => [ " fail", :alert, "Falhou" ] }.freeze
  URL_IN_TEXT = %r{https?://[^\s<>"]+}

  def whatsapp_initials_for(name)
    name.to_s.delete("@+").split.first(2).map { |word| word[0] }.join.upcase.presence || "WA"
  end

  # Hora na lista: hoje, a hora; ontem, "Ontem"; antes, o dia.
  def whatsapp_time_label(time)
    return "" unless time
    return l(time, format: "%H:%M") if time.to_date == Date.current

    time.to_date == Date.yesterday ? "Ontem" : l(time, format: "%d/%m")
  end

  def whatsapp_day_label(time)
    date = time.to_date
    return "Hoje" if date == Date.current
    return "Ontem" if date == Date.yesterday

    l(date, format: "%d/%m/%Y")
  end

  # Empresa do vínculo ou a identificação da pessoa (telefone, @usuário).
  def whatsapp_identification(conversation)
    conversation.contact&.company&.trade_name || conversation.lead&.company_name.presence || conversation.phone_label ||
      (conversation.username && "@#{conversation.username.delete_prefix('@')}") || "ID do WhatsApp"
  end

  def whatsapp_link_badge(conversation)
    return tag.span("Lead", class: "badge b-info") if conversation.lead_id
    return tag.span("Cliente", class: "badge b-good") if conversation.contact_id

    tag.span("Sem vínculo", class: "badge b-warn")
  end

  # Tempo até a janela fechar: "5h" ou "40 min". soon: menos de 2 horas.
  def whatsapp_window_left(conversation)
    seconds = (conversation.window_closes_at - Time.current).to_i
    seconds >= 3600 ? "#{seconds / 3600}h" : "#{[ seconds / 60, 1 ].max} min"
  end

  def whatsapp_window_soon?(conversation)
    conversation.window_open? && conversation.window_closes_at - Time.current < 2.hours
  end

  # Texto recebido ou enviado: escapado, com os links clicáveis (rel noopener noreferrer, nova aba).
  def whatsapp_message_text(text)
    html = ERB::Util.html_escape(text.to_s).to_str.gsub(URL_IN_TEXT) do |match|
      url, trailing = match.match(/\A(.*?)([.,;:!?)]*)\z/).captures # pontuação no fim fica fora do link
      href = CGI.unescapeHTML(url)
      tag.a(href, href: href, rel: "noopener noreferrer", target: "_blank").to_str + trailing
    end
    sanitize(html, tags: %w[a], attributes: %w[href rel target])
  end

  def whatsapp_message_status(message)
    css, icon_name, label = MESSAGE_STATUS.fetch(message.status) { return nil }
    tag.span(class: "st#{css}") { safe_join([ icon(icon_name, size: 14, stroke: 2), label ]) }
  end

  def whatsapp_file_name(message)
    name = message.media.attached? ? message.media.filename.to_s : message.media_filename
    ActiveStorage::Filename.new(name.presence || "arquivo").sanitized
  end

  private

  def whatsapp_time(value)
    l(value, format: "%d/%m %H:%M") if value
  end

  def whatsapp_sync_steps(account)
    contacts = if account.contacts_synced_at then [ :done, whatsapp_time(account.contacts_synced_at) ]
    elsif account.contacts_sync_request_id? then [ :cur, "pedido enviado" ]
    else [ :todo, nil ]
    end
    history = if account.history_sync_error? then [ :todo, "não compartilhado no celular" ]
    elsif account.history_synced_at then [ :done, "#{whatsapp_time(account.history_synced_at)} · 100%" ]
    elsif account.history_sync_request_id? then [ :cur, account.history_sync_progress ? "#{account.history_sync_progress}%" : "pedido enviado" ]
    else [ :todo, nil ]
    end
    [ [ "Contatos sincronizados", *contacts ], [ "Histórico sincronizado", *history ] ]
  end

  def whatsapp_registration_step(account)
    return [ "Número registrado", :done, whatsapp_time(account.registered_at) ] if account.registered_at
    return [ "Número registrado", :cur, "aguardando o PIN" ] if account.registration_pending?

    [ "Número registrado", account.connected? ? :done : :todo, ("já registrado na Cloud API" if account.connected?) ]
  end
end
