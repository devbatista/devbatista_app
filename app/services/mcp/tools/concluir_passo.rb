module Mcp
  module Tools
    # "Feito" da lista Próximos passos, com a mesma regra da tela (NextStepCompletion).
    class ConcluirPasso < Base
      include CommercialData

      tool_name "concluir_passo"
      title "Concluir próximo passo"
      description <<~TEXT.squish
        Conclui o próximo passo de um lead ou de uma oportunidade em aberto: grava o que foi feito como interação
        de hoje no histórico (como registrar_interacao) e, junto, define o novo próximo passo (proximo_passo +
        proximo_passo_em, os dois obrigatórios) OU marca como perdido (marcar_perdido: true + motivo, um dos
        motivos_perda de opcoes_comerciais). Um dos dois é obrigatório: nenhum item sai da lista sem próximo passo
        ou sem ser marcado como perdido. Só marque como perdido quando o usuário pedir.
      TEXT
      writes
      input_schema(
        properties: {
          tipo: { type: "string", enum: %w[lead oportunidade] },
          id: { type: "string", description: "Id do lead ou da oportunidade" },
          o_que_foi_feito: { type: "string", description: "O que foi feito ou combinado" },
          tipo_interacao: { type: "string", enum: Interaction::KIND_LABELS.keys },
          proximo_passo: { type: "string", description: "A próxima ação" },
          proximo_passo_em: { type: "string", pattern: DATE_TIME_PATTERN,
                              description: "AAAA-MM-DDTHH:MM, horário de Brasília; só a data vale às 09:00" },
          marcar_perdido: { type: "boolean", description: "Em vez do próximo passo, marca como perdido" },
          motivo: { type: "string", description: "Com marcar_perdido: um dos motivos_perda de opcoes_comerciais" },
          detalhes: { type: "string", description: "Com marcar_perdido: detalhes da perda" }
        },
        required: %w[tipo id o_que_foi_feito tipo_interacao], additionalProperties: false
      )

      def execute(tipo:, id:, o_que_foi_feito:, tipo_interacao:, proximo_passo: nil, proximo_passo_em: nil,
                  marcar_perdido: false, motivo: nil, detalhes: nil)
        record = authorize((tipo == "lead" ? Lead : Opportunity).find(id), :update?)
        authorize(Interaction, :create?)
        fail!("Escolha um: próximo passo (proximo_passo + proximo_passo_em) ou marcar_perdido, não os dois.") if marcar_perdido && (proximo_passo || proximo_passo_em)

        completion = NextStepCompletion.new(
          record: record, user: user, notes: o_que_foi_feito, kind: tipo_interacao, outcome: outcome(marcar_perdido, proximo_passo, proximo_passo_em),
          next_step: proximo_passo, next_step_on: next_step_time!(proximo_passo_em), lost_reason: motivo, lost_details: detalhes
        )
        fail!("#{completion.errors.full_messages.to_sentence}.") unless completion.save

        { interacao: interaction_data(completion.interaction),
          tipo => (record.is_a?(Lead) ? lead_details(record.reload) : opportunity_details(record.reload)) }
      end

      private

      def outcome(lose, next_step, next_step_at)
        return "lost" if lose

        "next_step" if next_step || next_step_at
      end
    end
  end
end
