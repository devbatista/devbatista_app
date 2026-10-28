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
