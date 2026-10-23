module Mcp
  module Tools
    # Proposta sempre nasce como Rascunho: enviar ao cliente, aprovar e recusar ficam na tela.
    class CriarProposta < Base
      include CommercialData

      tool_name "criar_proposta"
      title "Criar proposta (rascunho)"
      description <<~TEXT.squish
        Cria uma proposta como Rascunho, com um ou mais itens do catálogo de serviços. O destinatário é uma empresa
        (empresa_id) ou um lead (lead_id); com oportunidade_id, a empresa vem da oportunidade. O preço do item, se não
        vier, é o preço padrão do serviço; a recorrência, mensal para serviço recorrente e avulsa para os demais.
        O contato, se não vier, é o principal da empresa. Envio ao cliente e aprovação são feitos pela tela.
      TEXT
      writes
      input_schema(
        properties: {
          titulo: { type: "string" },
          empresa_id: { type: "string" }, lead_id: { type: "string" }, oportunidade_id: { type: "string" },
          contato_id: { type: "string", description: "Contato da empresa; padrão: o principal" },
          responsavel_id: { type: "string", description: "Padrão: você" },
          valida_ate: CommercialData::DATE.merge(description: "AAAA-MM-DD; padrão: daqui a 15 dias"),
          descricao: { type: "string", description: "Escopo e contexto, aparece no PDF" },
          condicoes_pagamento: { type: "string" }, prazo_entrega: { type: "string" }, observacoes: { type: "string" },
          itens: {
            type: "array", minItems: 1,
            items: {
              type: "object",
              properties: {
                servico_id: { type: "string", description: "Serviço do catálogo (opcoes_comerciais)" },
                descricao: { type: "string" },
                recorrencia: { type: "string", enum: ProposalItem::RECURRENCE_LABELS.keys },
                preco: { type: "number", minimum: 0, description: "Em reais" }
              },
              required: [ "servico_id" ], additionalProperties: false
            }
          }
        },
        required: %w[titulo itens], additionalProperties: false
      )

      def execute(titulo:, itens:, empresa_id: nil, lead_id: nil, oportunidade_id: nil, contato_id: nil, responsavel_id: nil,
                  valida_ate: nil, descricao: nil, condicoes_pagamento: nil, prazo_entrega: nil, observacoes: nil)
        opportunity = oportunidade_id && authorize(Opportunity.find(oportunidade_id))
        proposal = Proposal.new(
          title: titulo, status: "draft", company_id: empresa_id || opportunity&.company_id, lead_id: lead_id,
          opportunity: opportunity, contact_id: contato_id, user_id: responsavel_id || user.id,
          valid_until: valida_ate || Date.current + 15, description: descricao, payment_terms: condicoes_pagamento,
          delivery_terms: prazo_entrega, notes: observacoes
        )
        itens.each_with_index do |item, index|
          service = Service.available.find_by(id: item[:servico_id])
          fail!("Item #{index + 1}: serviço não encontrado ou inativo no catálogo.") unless service

          proposal.items.build(service: service, description: item[:descricao], recurrence: item[:recorrencia],
                               price: item[:preco], position: index + 1)
        end
        authorize(proposal, :create?).save!

        proposal_details(proposal)
      end
    end
  end
end
