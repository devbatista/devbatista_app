module Mcp
  module Tools
    class ConcluirPendencia < Base
      include AgentData

      tool_name "concluir_pendencia"
      title "Concluir ordem do agente"
      description <<~TEXT.squish
        Marca como concluída uma ordem que o administrador deixou para você (ler_pendencias), com a resposta:
        o que foi feito ou por que não foi possível. A resposta aparece no escritório.
      TEXT
      writes
      input_schema(
        properties: {
          agente: AgentData::AGENT,
          ordem_id: { type: "string", description: "Id da ordem (ler_pendencias)" },
          resposta: { type: "string", maxLength: 5000 }
        },
        required: %w[agente ordem_id resposta], additionalProperties: false
      )

      def execute(agente:, ordem_id:, resposta:)
        agent = find_agent(agente, :update?)
        order = agent.orders.find_by(id: ordem_id)
        fail!("Ordem não encontrada entre as do agente #{agent.key}.") unless order
        fail!("Esta ordem já foi concluída em #{I18n.l(order.completed_at, format: '%d/%m/%Y %H:%M')}.") if order.status_completed?

        authorize(order, :update?).complete!(resposta)
        order_data(order)
      end
    end
  end
end
