module Mcp
  module Tools
    class OpcoesComerciais < Base
      tool_name "opcoes_comerciais"
      title "Opções do comercial"
      description <<~TEXT.squish
        Valores aceitos pelo Comercial do Admin DevBatista: origens e status de lead, etapas de oportunidade,
        tipos de interação, motivos de perda, serviços do catálogo e usuários ativos (responsáveis).
        Consulte antes de criar ou alterar leads, oportunidades e propostas, e use as chaves e ids daqui.
      TEXT
      read_only

      def execute
        authorize(Lead, :index?)

        {
          origens_lead: Lead::ORIGIN_LABELS,
          status_lead: Lead::STATUS_LABELS,
          etapas_oportunidade: Opportunity::STAGE_LABELS,
          tipos_interacao: Interaction::KIND_LABELS,
          motivos_perda: Setting[:loss_reasons],
          servicos: Service.available.map do |service|
            { id: service.id, nome: service.name, categoria: service.category, tipo: service.kind_label,
              preco_padrao: reais(service.default_price_cents) }
          end,
          usuarios: User.active.by_name.includes(:role).map do |person|
            { id: person.id, nome: person.name, perfil: person.role.name, voce: person == user }
          end
        }
      end
    end
  end
end
