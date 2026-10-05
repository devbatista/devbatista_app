# Rotina diária dos domínios (RF 31): nos marcos configurados (60, 30 e 7 dias antes do
# vencimento) avisa Desenvolvedor e Administrador. Sem renovação automática o alerta é crítico.
# Domínio que venceu sem renovação registrada também gera alerta crítico.
# Idempotente: o aviso tem dedup_key por domínio, vencimento e marco.
class DomainAlertsJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    days = Setting[:domain_alert_days].map(&:to_i).sort
    routes = Rails.application.routes.url_helpers

    # Venceu sem renovação registrada: um alerta crítico por vencimento.
    Domain.includes(:company).where(expires_on: (today - 30)...today).find_each do |domain|
      Notification.deliver!(kind: "domain_expiring", level: "crit", notifiable: domain, path: routes.domains_path,
                            title: "Domínio #{domain.name} (#{domain.company.trade_name}) venceu em #{I18n.l(domain.expires_on)} sem renovação registrada",
                            dedup_key: "domain-#{domain.id}-#{domain.expires_on}-expired")
    end

    Domain.includes(:company).expiring_within(days.max, today).find_each do |domain|
      milestone = domain.alert_window(today, days)
      next unless milestone

      left = domain.days_left(today)
      Notification.deliver!(
        kind: "domain_expiring", notifiable: domain,
        level: !domain.auto_renew? || milestone == days.min ? "crit" : "warn",
        title: "Domínio #{domain.name} (#{domain.company.trade_name}) vence em #{left} #{left == 1 ? 'dia' : 'dias'}#{' · sem renovação automática' unless domain.auto_renew?}",
        path: routes.domains_path, dedup_key: "domain-#{domain.id}-#{domain.expires_on}-#{milestone}d"
      )
    end
  end
end
