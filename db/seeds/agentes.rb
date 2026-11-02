# Escritório de agentes de IA: um dia de exemplo, com cada agente num status diferente, um pedido de
# aprovação pendente, uma decisão já lida e ordens. Só fora de produção e só se ainda não há eventos.
module Seeds
  module Agentes
    # [agente, minutos atrás, status, título, resumo, payload]
    EVENTS = [
      [ "ops", 190, "working", "Checagem diária dos servidores", "Conferindo disco, memória e certificados dos 4 servidores.", nil ],
      [ "ops", 175, "done", "Checagem diária dos servidores", "Tudo dentro do normal. O certificado de painel.cliente.com.br vence em 21 dias.",
        { servidores: 4, alertas: 0, certificado_vencendo: "painel.cliente.com.br" } ],
      [ "ops", 12, "working", "Revisando os backups da noite", "Conferindo se os dumps do PostgreSQL chegaram ao S3.", nil ],
      [ "sol", 150, "working", "Qualificando os leads do site", "5 leads novos do diagnóstico desde ontem.", nil ],
      [ "sol", 40, "awaiting_approval", "Enviar follow-up para 3 leads qualificados",
        "Rascunhei um WhatsApp para Padaria Sol, Oficina do Zé e Clínica Vida, que pediram proposta e não responderam há 5 dias. " \
        "Posso enviar o template proposta_enviada?", { leads: [ "Padaria Sol", "Oficina do Zé", "Clínica Vida" ], template: "proposta_enviada" } ],
      [ "mia", 95, "done", "Calendário de posts de novembro", "12 posts sugeridos para o Instagram e o LinkedIn, com legenda e tema.", nil ],
      [ "leo", 70, "awaiting_approval", "Aumentar a verba da campanha de diagnóstico",
        "CPL de R$ 18 nos últimos 7 dias, abaixo da meta de R$ 25. Proponho subir de R$ 40 para R$ 60 por dia.", nil ],
      [ "fin", 30, "error", "Conciliação das contas a receber", "Não consegui ler o extrato do banco: o arquivo de hoje não chegou.", nil ]
    ].freeze

    def self.run
      return if AgentEvent.exists?

      rafael = User.find_by!(email: "rafael@devbatista.com.br")
      agents = Agent.all.index_by(&:key)
      EVENTS.each do |key, minutes, status, title, summary, payload|
        AgentEvent.create!(agent: agents.fetch(key), status: status, title: title, summary: summary, payload: payload,
                           created_at: minutes.minutes.ago)
      end

      # Pedido de ontem, já decidido e lido pelo agente.
      AgentEvent.create!(agent: agents.fetch("mia"), status: "awaiting_approval", title: "Publicar o post do case Grupo Norte",
                         summary: "Texto e imagem prontos.", created_at: 1.day.ago)
                .update!(decision: "approved", decided_at: 23.hours.ago, decided_by: rafael, decision_read_at: 20.hours.ago)

      AgentOrder.create!(agent: agents.fetch("sol"), user: rafael, body: "Priorize os leads que vieram do e-book esta semana.", created_at: 2.hours.ago)
      AgentOrder.create!(agent: agents.fetch("fin"), user: rafael, body: "Me avise quando o extrato chegar e refaça a conciliação.", created_at: 20.minutes.ago)
      AgentOrder.create!(agent: agents.fetch("ops"), user: rafael, body: "Confira o certificado do painel do cliente.", created_at: 3.hours.ago,
                         delivered_at: 190.minutes.ago)
                .complete!("Verificado: vence em 21 dias, com renovação automática pelo Let's Encrypt.")
    end
  end
end

Seeds::Agentes.run
