# Agentes IA → Escritório (docs/specs/escritorio-agentes): a planta com uma sala por agente e o
# painel do agente selecionado. Sem agente na URL, abre o primeiro com aprovação pendente.
class EscritorioController < ApplicationController
  def show
    authorize Agent, :index?
    @agents = Agent.preload_latest_events(policy_scope(Agent).active.ordered.to_a)
    @pending = AgentEvent.decision_pending.where(agent: @agents).group(:agent_id).count
    @agent = @agents.find { |agent| agent.key == params[:agente] } || @agents.find { |agent| @pending[agent.id] } || @agents.first
  end
end
