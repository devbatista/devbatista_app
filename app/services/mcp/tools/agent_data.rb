# Tools do escritório de agentes (docs/specs/escritorio-agentes): o agente se identifica pela chave
# em cada chamada, porque todos usam o mesmo conector. Respostas com chaves em português e os
# rótulos junto das chaves dos enums.
module Mcp
  module Tools
    module AgentData
      AGENT = { type: "string", description: "Sua chave de agente (ex.: ops, sol, mia, leo, fin)" }.freeze

      private

      # Confere a área antes de procurar, para quem não tem acesso não descobrir as chaves.
      def find_agent(key, query = :show?)
        authorize(Agent, :index?)
        agent = Agent.active.find_by(key: key.to_s.strip.downcase)
        fail!("Agente \"#{key}\" não encontrado ou inativo. Chaves ativas: #{Agent.active.ordered.pluck(:key).join(', ')}.") unless agent

        authorize(agent, query)
      end

      def event_data(event)
        {
          id: event.id, agente: event.agent.key, status: event.status, status_rotulo: event.status_label,
          titulo: event.title, resumo: event.summary, precisa_aprovacao: event.needs_approval,
          decisao: event.decision, decisao_rotulo: event.decision_label, observacao: event.decision_note,
          decidido_em: event.decided_at&.iso8601, registrado_em: event.created_at.iso8601
        }
      end

      def order_data(order)
        {
          id: order.id, texto: order.body, status: order.status, status_rotulo: order.status_label,
          por: order.user.name, criada_em: order.created_at.iso8601, resposta: order.response,
          concluida_em: order.completed_at&.iso8601
        }
      end

      def office_link(agent)
        link(:office, agente: agent.key)
      end
    end
  end
end
