# Rotina diária dos contratos (RF 17):
# - contrato ativo a até N dias do término (maior antecedência configurada) vira "Próximo do vencimento";
# - nos marcos configurados (60, 30 e 15 dias) gera o alerta para Comercial e Administrador;
# - contrato sem renovação automática que passou do término vira "Encerrado".
# Idempotente: rodar duas vezes no mesmo dia não duplica alerta nem histórico.
class ContractAlertsJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    days = Setting[:contract_alert_days].map(&:to_i).sort.reverse
    window = days.max

    Contract.active.where(end_date: today..(today + window.days)).find_each { |c| c.update!(status: "expiring") }

    Contract.expiring.where("end_date < ?", today).where.not(renewal: "automatic").find_each { |c| c.update!(status: "ended") }

    Contract.expiring.includes(:company).where(end_date: today..(today + window.days)).find_each do |contract|
      left = contract.days_left(today)
      milestone = days.select { |d| left <= d }.min
      next unless milestone

      Notification.deliver!(
        kind: "contract_expiring",
        level: left <= days.min ? "crit" : "warn",
        title: "Contrato #{contract.code} de #{contract.company.trade_name} vence em #{left} #{left == 1 ? 'dia' : 'dias'}",
        path: Rails.application.routes.url_helpers.contract_path(contract),
        notifiable: contract,
        dedup_key: "contract-#{contract.id}-#{contract.end_date}-#{milestone}d"
      )
    end
  end
end
