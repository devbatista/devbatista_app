module Mcp
  module Tools
    # Edita proposta em Rascunho, Enviada ou Visualizada, como a tela. Não muda o status: enviar,
    # aprovar e recusar ficam na tela.
    class AtualizarProposta < Base
      include CommercialData

      PROPOSAL_FIELDS = {
        titulo: :title, empresa_id: :company_id, lead_id: :lead_id, oportunidade_id: :opportunity_id,
        contato_id: :contact_id, responsavel_id: :user_id, valida_ate: :valid_until, descricao: :description,
        condicoes_pagamento: :payment_terms, prazo_entrega: :delivery_terms, observacoes: :notes
      }.freeze

      tool_name "atualizar_proposta"
      title "Atualizar proposta"
      description <<~TEXT.squish
        Altera uma proposta em Rascunho, Enviada ou Visualizada (aprovada, recusada ou expirada não muda): só os campos
        enviados mudam; null limpa o campo. Em itens, cada item com id (de ver_proposta) altera aquele item, com
        remover: true o exclui da proposta; sem id, adiciona um item novo (servico_id obrigatório; sem preço, usa o
        preço padrão do serviço). Itens não citados ficam como estão. O total é recalculado. Não muda o status nem
        envia ao cliente: se a proposta já foi enviada, gere o PDF de novo e envie pela tela.
      TEXT
      writes
      input_schema(
        properties: {
          id: { type: "string" },
          titulo: { type: "string" },
          empresa_id: TEXT, lead_id: TEXT, oportunidade_id: TEXT,
          contato_id: TEXT.merge(description: "Contato da empresa; ao trocar a empresa sem informar, vira o principal"),
          responsavel_id: { type: "string" },
          valida_ate: { type: "string", format: "date", description: "AAAA-MM-DD" },
          descricao: TEXT, condicoes_pagamento: TEXT, prazo_entrega: TEXT, observacoes: TEXT,
          itens: {
            type: "array", minItems: 1,
            items: {
              type: "object",
              properties: {
                id: { type: "string", description: "Item existente (ver_proposta); sem id, é item novo" },
                servico_id: { type: "string", description: "Serviço do catálogo (opcoes_comerciais)" },
                descricao: TEXT,
                recorrencia: { type: "string", enum: ProposalItem::RECURRENCE_LABELS.keys },
                preco: { type: "number", minimum: 0, description: "Em reais" },
                remover: { type: "boolean", description: "true exclui o item da proposta" }
              },
              additionalProperties: false
            }
          }
        },
        required: [ "id" ], additionalProperties: false
      )

      def execute(id:, itens: nil, **fields)
        proposal = authorize(Proposal.find(id), :update?)
        fail!("Envie ao menos um campo para alterar.") if fields.empty? && itens.nil?
        fail!("Proposta #{proposal.status_label.downcase} não pode mais ser editada.") unless proposal.editable?

        attributes = attributes_from(fields, PROPOSAL_FIELDS)
        if (opportunity_id = attributes[:opportunity_id])
          opportunity = authorize(Opportunity.find(opportunity_id))
          attributes[:company_id] = opportunity.company_id unless attributes.key?(:company_id)
        end
        # Empresa nova sem contato informado: o contato antigo não é dela, vale o principal da nova.
        if attributes.key?(:company_id) && attributes[:company_id] != proposal.company_id && !attributes.key?(:contact_id)
          attributes[:contact_id] = nil
        end
        attributes[:items_attributes] = items_attributes(proposal, itens) if itens

        proposal.update!(attributes)
        proposal_details(proposal.reload)
      end

      private

      def items_attributes(proposal, itens)
        next_position = proposal.items.maximum(:position).to_i
        itens.each_with_index.map do |item, index|
          label = "Item #{index + 1}"
          existing = item[:id] && (proposal.items.find_by(id: item[:id]) || fail!("#{label}: item não encontrado nesta proposta."))
          fail!("#{label}: remover só vale para item existente (informe o id).") if item[:remover] && !existing
          next { id: existing.id, _destroy: true } if item[:remover]
          fail!("#{label}: informe o servico_id do item novo.") if !existing && item[:servico_id].blank?

          if item[:servico_id] && item[:servico_id] != existing&.service_id && !Service.available.exists?(id: item[:servico_id])
            fail!("#{label}: serviço não encontrado ou inativo no catálogo.")
          end

          attrs = { servico_id: :service_id, descricao: :description, recorrencia: :recurrence, preco: :price }
                  .each_with_object({}) { |(key, attr), memo| memo[attr] = item[key] if item.key?(key) }
          # Sem service_id o accepts_nested_attributes_for descarta o item (reject_if do Proposal).
          existing ? { service_id: existing.service_id, **attrs, id: existing.id } : attrs.merge(position: next_position += 1)
        end
      end
    end
  end
end
