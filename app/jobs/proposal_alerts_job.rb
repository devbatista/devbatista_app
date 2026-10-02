# Rotina diária das propostas (RF 10):
# - Enviada ou Visualizada passa a Expirada no dia seguinte ao fim da validade;
# - N dias antes (Configurações, padrão 3) o responsável recebe o aviso.
# Idempotente: o aviso tem dedup_key.
class ProposalAlertsJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    Proposal.where(status: %w[sent viewed]).where("valid_until < ?", today).find_each { |p| p.update!(status: "expired") }

    days = Setting[:proposal_alert_days].to_i
    Proposal.includes(:company, :lead, :user).where(status: %w[sent viewed], valid_until: today..(today + days)).find_each do |proposal|
      left = proposal.days_to_expire(today)
      Notification.deliver!(
        kind: "proposal_expiring", level: left <= 1 ? "crit" : "warn", users: [ proposal.user ],
        title: "Proposta “#{proposal.title}” para #{proposal.recipient_name} expira #{left.zero? ? 'hoje' : "em #{left} #{left == 1 ? 'dia' : 'dias'}"}",
        path: Rails.application.routes.url_helpers.proposal_path(proposal), notifiable: proposal,
        dedup_key: "proposal-#{proposal.id}-#{proposal.valid_until}"
      )
    end
  end
end
