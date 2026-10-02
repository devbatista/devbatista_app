module CommercialHelper
  PROPOSAL_TONES = { "draft" => "mute", "sent" => "info", "viewed" => "blue", "approved" => "good", "rejected" => "crit", "expired" => "warn" }.freeze
  LEAD_TONES = { "new" => "info", "contacted" => "blue", "qualified" => "good", "converted" => "good", "lost" => "crit" }.freeze
  STAGE_TONES = { "meeting" => "blue", "proposal" => "info", "negotiation" => "warn", "won" => "good", "lost" => "crit" }.freeze

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
