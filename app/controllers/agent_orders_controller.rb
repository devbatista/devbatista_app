# "Deixar uma ordem" no painel do agente. O agente lê na próxima execução (ler_pendencias).
class AgentOrdersController < ApplicationController
  def create
    agent = authorize Agent.find_by!(key: params[:agent_id]), :show?
    order = authorize agent.orders.new(body: params.expect(agent_order: [ :body ])[:body], user: current_user)

    if order.save
      respond_to do |format|
        format.turbo_stream { render turbo_stream: refreshed(agent, agent.orders.new) }
        format.html { redirect_to escritorio_path(agente: agent.key), notice: "Ordem deixada para #{agent.name}." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: refreshed(agent, order).first, status: :unprocessable_content }
        format.html { redirect_to escritorio_path(agente: agent.key), alert: order.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def refreshed(agent, order)
    [ turbo_stream.replace(helpers.dom_id(agent, :order_form), partial: "agents/order_form", locals: { agent: agent, order: order }),
      turbo_stream.replace(helpers.dom_id(agent, :log), partial: "agents/log", locals: { agent: agent }) ]
  end
end
