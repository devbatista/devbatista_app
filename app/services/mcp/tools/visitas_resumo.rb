module Mcp
  module Tools
    # Os seis indicadores da tela Visitas do site (Marketing::SiteVisitsController), com o período
    # anterior, a variação e a série para o gráfico.
    class VisitasResumo < Base
      include SiteVisitsData

      tool_name "visitas_resumo"
      title "Resumo das visitas do site"
      description <<~TEXT.squish
        Visitas de pessoas ao site devbatista.com no período: visitantes únicos, visitas, páginas vistas,
        páginas por visita, taxa de rejeição (% de visitas de uma página só e menos de 10 s) e duração média
        (segundos), com o período anterior de mesmo tamanho e a variação em %. Traz a série por hora (hoje,
        ontem), dia ou mês (12m), com zero onde não houve visita, e a data da primeira visita registrada:
        antes dela não há dados. O visitante único é contado por dia (quem volta no dia seguinte conta de
        novo). Robôs e agentes de IA não entram aqui (use acessos_ia). Para quebrar por canal, origem,
        página ou dispositivo, use visitas_por_dimensao.
      TEXT
      read_only
      input_schema(properties: { **PERIOD_PROPERTIES, **FILTER_PROPERTIES }, additionalProperties: false)

      def execute(periodo: nil, de: nil, ate: nil, **filters)
        stats = stats(periodo, de, ate, **filters)
        calculate { stats.summary.merge(link: link(:site_visits, periodo: stats.period.key.presence_in(SiteVisits::Stats::PERIODS.keys))) }
      end
    end
  end
end
