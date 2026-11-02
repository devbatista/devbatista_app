# Painel do agente no escritório (Turbo Frame "agent_panel"). As partes live (status, última tarefa,
# aprovações) e log (ordens e linha do tempo) são as que o broadcast recarrega; o campo "Deixar uma
# ordem" fica fora delas, para não perder o que foi digitado.
class AgentsController < ApplicationController
  before_action :set_agent

  def show
    return redirect_to escritorio_path(agente: @agent.key) unless turbo_frame_request?

    render partial: "agents/panel", locals: { agent: @agent }
  end

  def live
    render partial: "agents/live", locals: { agent: @agent }
  end

  def log
    render partial: "agents/log", locals: { agent: @agent }
  end

  private

  def set_agent
    @agent = authorize Agent.find_by!(key: params[:id]), :show?
  end
end
