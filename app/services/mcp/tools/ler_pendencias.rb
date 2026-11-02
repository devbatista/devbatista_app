module Mcp
  module Tools
    # O que o administrador deixou para o agente desde a última leitura. Marca as decisões como lidas
    # (não voltam na próxima chamada) e a primeira leitura de cada ordem; as ordens continuam aqui até
    # serem concluídas.
    class LerPendencias < Base
      include AgentData

      tool_name "ler_pendencias"
      title "Ler pendências do agente"
      description <<~TEXT.squish
        Chame no começo de cada execução. Devolve as ordens pendentes do administrador para você e as decisões
        (aprovado ou rejeitado, com observação) ainda não lidas dos seus pedidos de aprovação, além dos pedidos
        ainda sem decisão. As decisões devolvidas ficam marcadas como lidas. Conclua cada ordem atendida com
        concluir_pendencia.
      TEXT
      writes
      input_schema(properties: { agente: AgentData::AGENT }, required: %w[agente], additionalProperties: false)

      def execute(agente:)
        agent = find_agent(agente, :update?)
        orders = agent.orders.status_pending.includes(:user).order(:created_at).to_a
        decisions = agent.events.unread_decisions.includes(:agent).order(:decided_at).to_a
        mark_read(agent, orders, decisions)

        {
          agente: agent.key, ordens: orders.map { |order| order_data(order) },
          decisoes: decisions.map { |event| event_data(event) },
          aguardando_decisao: agent.pending_approvals.includes(:agent).map { |event| event_data(event) }
        }
      end

      private

      def mark_read(agent, orders, decisions)
        return if orders.empty? && decisions.empty?

        now = Time.current
        AgentOrder.where(id: orders.reject(&:delivered_at).map(&:id)).update_all(delivered_at: now, updated_at: now)
        AgentEvent.where(id: decisions.map(&:id)).update_all(decision_read_at: now, updated_at: now)
        agent.broadcast_office
      end
    end
  end
end
