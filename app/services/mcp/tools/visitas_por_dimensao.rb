module Mcp
  module Tools
    # Visitas do site agrupadas por canal, origem, UTM, página, dispositivo, dia da semana ou hora.
    class VisitasPorDimensao < Base
      include SiteVisitsData

      tool_name "visitas_por_dimensao"
      title "Visitas do site por dimensão"
      description <<~TEXT.squish
        Agrupa as visitas de pessoas ao site devbatista.com pela dimensão: canal (Assistentes de IA, E-mail,
        Campanha, Busca, Redes sociais, Outros sites, Direto), assistente_ia (ChatGPT, Perplexity…), origem
        (host da referência), utm_source, utm_medium, utm_campaign, pagina (as visitas que viram a página; a
        duração é o tempo médio na página), pagina_entrada, pagina_saida, dispositivo, navegador, sistema,
        dia_da_semana ou hora (fuso de Brasília). Cada linha traz visitantes, visitas, páginas vistas, % das
        visitas do período, taxa de rejeição e duração média em segundos; o que passar do limite vem somado
        em "outros". Grupos de UTM com menos de 3 visitantes aparecem sem o rótulo. Aceita os mesmos
        filtros de visitas_resumo, combináveis.
      TEXT
      read_only
      input_schema(
        properties: {
          dimensao: { type: "string", enum: SiteVisits::Stats::DIMENSIONS },
          **PERIOD_PROPERTIES, **FILTER_PROPERTIES, limite: LIMIT
        },
        required: %w[dimensao],
        additionalProperties: false
      )

      def execute(dimensao:, periodo: nil, de: nil, ate: nil, limite: nil, **filters)
        stats = stats(periodo, de, ate, **filters)
        calculate { stats.by_dimension(dimensao, limit: limit(limite)) }
      end
    end
  end
end
