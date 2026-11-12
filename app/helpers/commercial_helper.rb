module CommercialHelper
  PROPOSAL_TONES = { "draft" => "mute", "sent" => "info", "viewed" => "blue", "approved" => "good", "rejected" => "crit", "expired" => "warn" }.freeze
  LEAD_TONES = { "new" => "info", "contacted" => "blue", "qualified" => "good", "converted" => "good", "lost" => "crit" }.freeze
  STAGE_TONES = { "meeting" => "blue", "proposal" => "info", "negotiation" => "warn", "won" => "good", "lost" => "crit" }.freeze

  # ---------- Próximos passos ----------

  # Caminho do "Feito" (action :done) ou do "Adiar" (:postpone) de um lead ou oportunidade.
  def next_step_action_path(action, record, **params)
    public_send(:"#{action}_#{record.is_a?(Lead) ? 'lead' : 'opportunity'}_next_step_path", record, **params)
  end

  # Ficha do registro: a página do lead ou a gaveta da oportunidade (que não tem página própria).
  def next_step_record_link(item, **options)
    return link_to(item.name, lead_path(item.record), **options) if item.lead?

    drawer_link_to(item.name, edit_opportunity_path(item.record), **options)
  end

  # Quando, na linha: só a hora em Hoje e Amanhã; dia e hora nos demais grupos.
  def next_step_when(time, group)
    return "—" unless time

    group.in?(%w[hoje amanha]) ? l(time, format: "%H:%M") : l(time, format: "%d/%m %H:%M")
  end

  def next_step_status_badge(item)
    status_badge(item.status_label, (item.lead? ? LEAD_TONES : STAGE_TONES)[item.status])
  end

  # WhatsApp como link wa.me (com DDI 55), ou o número como veio se não der para montar.
  def next_step_whatsapp_link(number)
    return "—" if number.blank?

    wa_id = Whatsapp::Phone.wa_ids(number).first
    wa_id ? link_to(number, "https://wa.me/#{wa_id}", target: "_blank", rel: "noopener") : number
  end

  def proposal_badge(proposal)
    status_badge(proposal.status_label, PROPOSAL_TONES[proposal.status])
  end

  # Opções de serviço com o preço padrão e a recorrência sugerida, usadas pelo editor de itens.
  def service_options_for_items(selected = nil, extra = [])
    services = (Service.available.to_a | extra.compact)
    options_for_select(services.map do |s|
      [ s.name, s.id, { "data-price" => format("%.2f", s.default_price_cents / 100.0), "data-recurrence" => s.recurring? ? "monthly" : "one_off" } ]
    end, selected)
  end
end
