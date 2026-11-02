module Mcp
  module Tools
    # O agente conta o que está fazendo; o evento aparece na hora no escritório (broadcast).
    class RegistrarEvento < Base
      include AgentData

      tool_name "registrar_evento"
      title "Registrar evento do agente"
      description <<~TEXT.squish
        Registra no escritório o que você, agente, está fazendo: status, título e resumo. Status: working
        (Trabalhando), idle (Ocioso), awaiting_approval (Aguardando aprovação), done (Concluído) e error (Erro).
        Com precisa_aprovacao: true, o status vira Aguardando aprovação e o administrador aprova ou rejeita na
        tela; não execute a ação antes de ler a decisão com ler_pendencias numa próxima execução.
      TEXT
      writes
      input_schema(
        properties: {
          agente: AgentData::AGENT,
          status: { type: "string", enum: AgentEvent::STATUS_LABELS.keys },
          titulo: { type: "string", maxLength: 120, description: "Tarefa em poucas palavras" },
          resumo: { type: [ "string", "null" ], maxLength: 5000, description: "O que foi feito ou o que precisa ser aprovado, e por quê" },
          precisa_aprovacao: { type: "boolean", description: "Pede aprovação do administrador; padrão: false" },
          dados: { type: [ "object", "null" ], description: "Detalhes estruturados opcionais (até 20 KB), mostrados como JSON" }
        },
        required: %w[agente status titulo], additionalProperties: false
      )

      def execute(agente:, status:, titulo:, resumo: nil, precisa_aprovacao: false, dados: nil)
        agent = find_agent(agente, :update?)
        event = authorize(agent.events.new(status: status, title: titulo, summary: resumo, needs_approval: precisa_aprovacao,
                                           payload: dados), :create?)
        event.save!

        event_data(event).merge(link: office_link(agent))
      end
    end
  end
end
