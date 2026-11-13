# Formato dos registros do Comercial nas respostas das tools: chaves em português,
# valores em reais, rótulos junto das chaves dos enums e link para a tela.
module Mcp
  module Tools
    module CommercialData
      # Campo da tool → atributo do model, nas tools que criam ou alteram.
      LEAD_FIELDS = {
        nome: :name, empresa: :company_name, email: :email, telefone: :phone, whatsapp: :whatsapp, origem: :origin,
        servico_id: :service_id, responsavel_id: :user_id, entrada: :entered_on, observacoes: :notes,
        proximo_passo: :next_step, proximo_passo_em: :next_step_on
      }.freeze

      OPPORTUNITY_FIELDS = {
        titulo: :title, empresa_id: :company_id, servico_id: :service_id, responsavel_id: :user_id,
        valor_estimado: :estimated_value, probabilidade: :probability, previsao_fechamento: :expected_close_on,
        observacoes: :notes, proximo_passo: :next_step, proximo_passo_em: :next_step_on
      }.freeze

      TEXT = { type: [ "string", "null" ] }.freeze
      DATE = { type: [ "string", "null" ], format: "date", description: "AAAA-MM-DD" }.freeze
      # Data e hora do próximo passo. Só a data (como antes) vale às 09:00 (NextStepSchedulable).
      DATE_TIME_PATTERN = "^\\d{4}-\\d{2}-\\d{2}([T ]\\d{2}:\\d{2}(:\\d{2})?(Z|[+-]\\d{2}:?\\d{2})?)?$"
      NEXT_STEP_AT = {
        type: [ "string", "null" ], pattern: DATE_TIME_PATTERN,
        description: "AAAA-MM-DDTHH:MM, horário de Brasília; só a data (AAAA-MM-DD) vale às 09:00"
      }.freeze

      LEAD_PROPERTIES = {
        nome: { type: "string", description: "Pessoa de contato. Sem pessoa, use o nome da empresa" },
        empresa: TEXT, email: TEXT, telefone: TEXT, whatsapp: TEXT,
        origem: { type: "string", enum: Lead::ORIGIN_LABELS.keys },
        servico_id: TEXT.merge(description: "Serviço de interesse (opcoes_comerciais); vazio = a definir"),
        responsavel_id: { type: "string", description: "Usuário responsável (opcoes_comerciais); padrão: você" },
        entrada: DATE.merge(description: "Data de entrada, AAAA-MM-DD; padrão: hoje"),
        observacoes: TEXT, proximo_passo: TEXT, proximo_passo_em: NEXT_STEP_AT
      }.freeze

      OPPORTUNITY_PROPERTIES = {
        titulo: { type: "string" },
        empresa_id: { type: "string", description: "Empresa (buscar_empresas)" },
        servico_id: TEXT.merge(description: "Serviço do catálogo (opcoes_comerciais)"),
        responsavel_id: { type: "string", description: "Usuário responsável; padrão: você" },
        valor_estimado: { type: "number", minimum: 0, description: "Em reais" },
        probabilidade: { type: "integer", minimum: 0, maximum: 100, description: "Em %; padrão: o sugerido pela etapa" },
        previsao_fechamento: DATE, observacoes: TEXT, proximo_passo: TEXT, proximo_passo_em: NEXT_STEP_AT
      }.freeze

      private

      def attributes_from(args, fields)
        next_step_time!(args[:proximo_passo_em]) if args.key?(:proximo_passo_em)
        args.slice(*fields.keys).transform_keys(fields)
      end

      # proximo_passo_em → horário em Brasília; recusa texto que não seja data ou data e hora.
      def next_step_time!(value)
        return nil if value.blank?

        NextStepSchedulable.cast(value) || fail!("proximo_passo_em inválido (#{value}): use AAAA-MM-DD ou AAAA-MM-DDTHH:MM.")
      end

      # Horário em ISO 8601 com o fuso de Brasília (2026-11-12T14:30:00-03:00).
      def iso_time(time)
        time&.in_time_zone&.iso8601
      end

      def lead_data(lead)
        {
          id: lead.id, nome: lead.name, empresa: lead.company_name, email: lead.email, telefone: lead.phone,
          whatsapp: lead.whatsapp, origem: lead.origin, origem_rotulo: lead.origin_label,
          status: lead.status, status_rotulo: lead.status_label, servico: lead.service&.name,
          responsavel: lead.user.name, entrada: lead.entered_on,
          proximo_passo: lead.next_step, proximo_passo_em: iso_time(lead.next_step_on), link: link(:lead, lead)
        }
      end

      def lead_details(lead)
        lead_data(lead).merge(
          servico_id: lead.service_id, responsavel_id: lead.user_id, observacoes: lead.notes,
          empresa_cadastrada: lead.company && company_ref(lead.company),
          convertido_em: lead.converted_at, perdido_em: lead.lost_at,
          motivo_perda: lead.lost_reason, detalhes_perda: lead.lost_details
        )
      end

      def opportunity_data(opportunity)
        {
          id: opportunity.id, titulo: opportunity.title, empresa: company_ref(opportunity.company),
          etapa: opportunity.stage, etapa_rotulo: opportunity.stage_label,
          valor_estimado: reais(opportunity.estimated_value_cents), probabilidade: opportunity.probability,
          valor_ponderado: reais(opportunity.weighted_cents), previsao_fechamento: opportunity.expected_close_on,
          servico: opportunity.service&.name, responsavel: opportunity.user.name,
          proximo_passo: opportunity.next_step, proximo_passo_em: iso_time(opportunity.next_step_on),
          link: link(:edit_opportunity, opportunity)
        }
      end

      def opportunity_details(opportunity)
        opportunity_data(opportunity).merge(
          servico_id: opportunity.service_id, responsavel_id: opportunity.user_id,
          lead_id: opportunity.lead_id, observacoes: opportunity.notes, fechada_em: opportunity.closed_on,
          motivo_perda: opportunity.lost_reason, detalhes_perda: opportunity.lost_details
        )
      end

      def proposal_data(proposal)
        {
          id: proposal.id, codigo: proposal.code, titulo: proposal.title, destinatario: proposal.recipient_name,
          empresa_id: proposal.company_id, lead_id: proposal.lead_id, oportunidade_id: proposal.opportunity_id,
          status: proposal.status, status_rotulo: proposal.status_label, total: reais(proposal.total_cents),
          valida_ate: proposal.valid_until, responsavel: proposal.user.name, link: link(:proposal, proposal)
        }
      end

      def proposal_details(proposal)
        proposal_data(proposal).merge(
          contato: proposal.contact && { id: proposal.contact.id, nome: proposal.contact.name, email: proposal.contact.email },
          descricao: proposal.description, condicoes_pagamento: proposal.payment_terms,
          prazo_entrega: proposal.delivery_terms, observacoes: proposal.notes, mrr: reais(proposal.mrr_cents),
          dias_para_expirar: (proposal.days_to_expire if proposal.editable?),
          enviada_em: proposal.sent_at, visualizada_em: proposal.viewed_at, decidida_em: proposal.decided_on,
          motivo_recusa: proposal.rejection_reason, detalhes_recusa: proposal.rejection_details,
          itens: proposal.items.map do |item|
            { id: item.id, servico: item.service.name, servico_id: item.service_id, descricao: item.description,
              recorrencia: item.recurrence, recorrencia_rotulo: item.recurrence_label,
              preco_padrao: reais(item.default_price_cents), preco: reais(item.price_cents) }
          end
        )
      end

      def interaction_data(interaction)
        { tipo: interaction.kind, tipo_rotulo: interaction.kind_label, data: interaction.occurred_on,
          notas: interaction.notes, por: interaction.user.name }
      end

      def company_ref(company)
        { id: company.id, nome: company.trade_name }
      end
    end
  end
end
