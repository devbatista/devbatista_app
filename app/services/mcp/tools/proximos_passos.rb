module Mcp
  module Tools
    # Mesma lista da tela Comercial → Próximos passos (NextStepList): leads e oportunidades em aberto
    # pela data e hora do próximo passo, do mais antigo para o mais novo.
    class ProximosPassos < Base
      include CommercialData

      DEFAULT_LIMIT = 50
      MAX_LIMIT = 200
      PERIOD = {
        type: "string", pattern: DATE_TIME_PATTERN,
        description: "AAAA-MM-DD ou AAAA-MM-DDTHH:MM, horário de Brasília"
      }.freeze

      tool_name "proximos_passos"
      title "Próximos passos"
      description <<~TEXT.squish
        Lista única dos próximos passos de leads e oportunidades em aberto, ordenada pela data e hora da ação
        (do mais antigo para o mais novo). Chame no começo de uma sessão comercial para saber o que fazer.
        de/ate limitam a data do próximo passo (só a data: o dia inteiro). Os atrasados entram mesmo antes de
        `de`, salvo incluir_atrasados: false; os sem data só com incluir_sem_data: true. Cada item traz a
        ação, quando (ISO 8601, -03:00), se está atrasado, o status, o WhatsApp e a última interação.
        Ao concluir uma ação, use concluir_passo.
      TEXT
      read_only
      input_schema(
        properties: {
          de: PERIOD.merge(description: "A partir de, AAAA-MM-DD ou AAAA-MM-DDTHH:MM; padrão: sem limite"),
          ate: PERIOD.merge(description: "Até, AAAA-MM-DD (o dia inteiro) ou AAAA-MM-DDTHH:MM; padrão: sem limite"),
          incluir_atrasados: { type: "boolean", description: "Padrão: true" },
          incluir_sem_data: { type: "boolean", description: "Abertos sem próximo passo, no fim. Padrão: false" },
          tipo: { type: "string", enum: %w[lead oportunidade todos], description: "Padrão: todos" },
          limite: { type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "Padrão: #{DEFAULT_LIMIT}" }
        },
        additionalProperties: false
      )

      def execute(de: nil, ate: nil, incluir_atrasados: true, incluir_sem_data: false, tipo: "todos", limite: DEFAULT_LIMIT)
        authorize(:next_step, :index?)
        from = bound(de, :beginning_of_day)
        to = bound(ate, :end_of_day)
        fail!("`de` não pode ser depois de `ate`.") if from && to && from > to

        list = NextStepList.new(leads: policy_scope(Lead), opportunities: policy_scope(Opportunity),
                                kind: tipo.presence_in(NextStepList::KINDS), from: from, to: to,
                                include_overdue: incluir_atrasados, include_undated: incluir_sem_data)
        items = list.items(limit: limite.to_i.clamp(1, MAX_LIMIT))
        last = NextStepList.last_interactions(items.map(&:record))

        { agora: iso_time(list.now), total: list.total, mostrando: items.size,
          proximos_passos: items.map { |item| item_data(item, list, last[[ item.record.class.name, item.record.id ]]) } }
      end

      private

      # Só a data: o começo ou o fim do dia; com hora, o horário informado.
      def bound(value, day_edge)
        return nil if value.blank?

        text = value.to_s.strip
        time = NextStepSchedulable.cast(text) || fail!("Data inválida (#{value}): use AAAA-MM-DD ou AAAA-MM-DDTHH:MM.")
        text.match?(NextStepSchedulable::DATE_ONLY) ? time.public_send(day_edge) : time
      end

      def item_data(item, list, interaction)
        record = item.record
        {
          tipo: item.kind, id: record.id, nome: item.name, empresa: item.company, acao: item.action,
          quando: iso_time(item.at), atrasado: item.overdue?(list.now), grupo: list.group_of(item.at),
          status: item.status, status_rotulo: item.status_label, responsavel: record.user.name,
          whatsapp: item.whatsapp, link: item.lead? ? link(:lead, record) : link(:edit_opportunity, record),
          ultima_interacao: interaction && {
            data: interaction.occurred_on, tipo: interaction.kind, texto: interaction.notes.to_s.squish.truncate(160)
          }
        }
      end
    end
  end
end
