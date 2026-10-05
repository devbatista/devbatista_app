module TechnologyHelper
  ENV_TONES = { "production" => "good", "staging" => "info", "development" => "mute" }.freeze
  APP_TONES = { "active" => "good", "maintenance" => "warn", "disabled" => "mute" }.freeze
  INTEGRATION_TONES = { "active" => "good", "configuring" => "info", "disabled" => "mute" }.freeze
  PRODUCT_TONES = { "idea" => "blue", "development" => "info", "operating" => "good", "discontinued" => "mute" }.freeze
  SUBSCRIPTION_TONES = { "trial" => "info", "active" => "good", "delinquent" => "crit", "cancelled" => "mute" }.freeze

  def env_badge(record)
    status_badge(record.environment_label, ENV_TONES[record.environment])
  end

  def app_badge(app)
    tag.span(app.status_label, class: "badge b-#{APP_TONES[app.status]} dot-l")
  end

  def integration_badge(integration)
    tag.span(integration.status_label, class: "badge b-#{INTEGRATION_TONES[integration.status]} dot-l")
  end

  def product_badge(product)
    tag.span(product.status_label, class: "badge b-#{PRODUCT_TONES[product.status]} dot-l")
  end

  def subscription_badge(subscription)
    status_badge(subscription.status_label, SUBSCRIPTION_TONES[subscription.status])
  end

  def paid_by_badge(record)
    record.paid_by_devbatista? ? status_badge("DevBatista", "info") : status_badge("Cliente", "mute")
  end

  # Custo de serviço externo na moeda original, com o equivalente mensal em reais embaixo.
  def service_cost(service)
    period = { "monthly" => "/mês", "annual" => "/ano", "usage" => "" }[service.periodicity]
    sub = service.foreign? || service.annual? ? "≈ #{brl(service.monthly_brl_cents)}#{'/mês' if service.annual?}" : nil
    safe_join([ "#{money_in(service.cost_cents, service.currency)}#{period}", (tag.span(sub, class: "cell-sub") if sub) ].compact)
  end

  # Hospedagem da aplicação: nome e tipo ("Servidor · AWS" ou "Serviço externo").
  def hosting_cell(app)
    return tag.span("—", class: "muted") unless app.hosting

    if app.hosting.is_a?(Server)
      safe_join([ app.hosting.name, tag.span("Servidor · #{app.hosting.supplier.name}", class: "cell-sub") ])
    else
      safe_join([ app.hosting.name, tag.span("Serviço externo", class: "cell-sub") ])
    end
  end

  # Opções agrupadas de hospedagem: servidores e serviços externos.
  def hosting_options(app)
    servers = Server.includes(:supplier).by_name
    services = ExternalService.active.or(ExternalService.where(id: (app.hosting_id if app.hosting_type == "ExternalService"))).includes(:company).by_name
    grouped_options_for_select([ [ "Servidores", servers.map { |s| [ s.hosting_label, "Server:#{s.id}" ] } ],
                                 [ "Serviços externos", services.map { |s| [ s.hosting_label, "ExternalService:#{s.id}" ] } ] ], app.hosting_key)
  end

  # Aplicações agrupadas por cliente, para selects de banco, integração e serviço externo.
  def app_options(selected)
    apps = App.includes(:company).order(:name).group_by(&:company).sort_by { |c, _| c.trade_name }
    grouped_options_for_select(apps.map { |c, list| [ c.trade_name, list.map { |a| [ "#{a.name} · #{a.environment_label}", a.id ] } ] }, selected)
  end

  def vault_hint
    "Caminho do item no cofre, nunca a credencial"
  end
end
