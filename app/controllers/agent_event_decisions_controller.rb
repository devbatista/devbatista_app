# Aprovar ou rejeitar um pedido do agente, com observação opcional. O agente lê a decisão na
# próxima execução (ler_pendencias).
class AgentEventDecisionsController < ApplicationController
  def create
    event = authorize AgentEvent.find(params[:agent_event_id]), :decide?
    agent = event.agent
    begin
      event.decide!(params[:decisao], by: current_user, note: params[:observacao])
      notice = "#{event.decision_label} · #{event.title}"
    rescue ActiveRecord::RecordInvalid
      alert = "Não foi possível registrar a decisão: #{event.errors.full_messages.to_sentence}."
    end

    respond_to do |format|
      format.turbo_stream do
        agent.reload
        render turbo_stream: [ turbo_stream.replace(helpers.dom_id(agent, :panel), partial: "agents/live", locals: { agent: agent, alert: alert }),
                               turbo_stream.replace(helpers.dom_id(agent, :log), partial: "agents/log", locals: { agent: agent }) ],
               status: (alert ? :unprocessable_content : :ok)
      end
      format.html { redirect_to office_path(agente: agent.key), notice: notice, alert: alert }
    end
  end
end
