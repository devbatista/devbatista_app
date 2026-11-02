# Agentes IA → Eventos: tudo o que os agentes registraram, com filtros. Cada linha abre o agente
# no escritório.
class AgentEventsController < ApplicationController
  def index
    authorize AgentEvent
    @agents = Agent.ordered
    scope = policy_scope(AgentEvent).includes(:agent, :decided_by)
    @counts = scope.group(:status).count
    scope = scope.where(status: params[:status]) if AgentEvent.statuses.key?(params[:status])
    scope = scope.joins(:agent).where(agents: { key: params[:agente] }) if params[:agente].present?
    scope = filter_decision(scope)
    scope = scope.where(created_at: period_range) if params[:periodo].present?
    scope = apply_sort(scope, {
      "recentes" => [ "Mais recentes", ->(s) { s.recent } ],
      "antigos" => [ "Mais antigos", ->(s) { s.order(:created_at, :id) } ]
    })
    @events, @pager = paginate(scope)
  end

  private

  def filter_decision(scope)
    case params[:aprovacao]
    when "sem" then scope.where(needs_approval: false)
    when *AgentEvent.decisions.keys then scope.where(decision: params[:aprovacao])
    else scope
    end
  end

  def period_range
    case params[:periodo]
    when "hoje" then Time.current.all_day
    when "7d" then 7.days.ago..Time.current
    when "30d" then 30.days.ago..Time.current
    else ..Time.current
    end
  end
end
