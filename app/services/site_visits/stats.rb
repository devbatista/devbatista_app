# Números das visitas do site (docs/specs/visitas-do-site): o único cálculo, usado pela tela
# (Marketing::SiteVisitsController) e pelas tools do MCP (visitas_resumo, visitas_por_dimensao e
# acessos_ia), para os dois nunca divergirem. Só números agregados: nenhuma visita individual nem
# visitor_hash sai daqui.
#
#   period = SiteVisits::Stats.period("30d")                  # ou period(de: "2026-10-01", ate: "2026-10-31")
#   stats = SiteVisits::Stats.new(period, "canal" => "search")
#   stats.summary                                             # indicadores, período anterior e série
#   stats.by_dimension("pagina", limit: 10)
#   stats.ai_hits(group: "empresa")
#
# O visitante único é contado por dia: o sal do hash muda à meia-noite, então quem volta no dia
# seguinte é outro visitante. Somar os dias e contar os hashes distintos do período dá o mesmo número.
module SiteVisits
  class Stats
    class Invalid < StandardError; end

    PERIODS = {
      "hoje" => "Hoje", "ontem" => "Ontem", "7d" => "Últimos 7 dias", "30d" => "Últimos 30 dias",
      "este_mes" => "Este mês", "mes_passado" => "Mês passado", "12m" => "Últimos 12 meses"
    }.freeze
    DEFAULT_PERIOD = "7d"
    MAX_DAYS = 400
    BUCKETS = { hour: "hora", day: "dia", month: "mes" }.freeze

    # Visita de uma página só e com menos de 10 s.
    BOUNCE_SECONDS = 10
    # Abaixo disso, o rótulo de UTM não aparece: um link mandado a uma pessoa só a identificaria.
    MIN_VISITORS = 3

    FILTERS = %w[canal origem utm_source utm_medium utm_campaign pagina pagina_entrada dispositivo].freeze
    DIMENSIONS = %w[canal assistente_ia origem utm_source utm_medium utm_campaign pagina pagina_entrada pagina_saida
                    dispositivo navegador sistema dia_da_semana hora].freeze
    HIDDEN_BELOW_MIN = %w[utm_source utm_medium utm_campaign].freeze
    CHRONOLOGICAL = %w[dia_da_semana hora].freeze
    WEEKDAYS = %w[Domingo Segunda Terça Quarta Quinta Sexta Sábado].freeze

    AI_GROUPS = %w[empresa agente tipo pagina dia].freeze
    AI_FILTERS = %w[empresa tipo verificacao pagina].freeze

    Period = Data.define(:key, :label, :range, :previous, :bucket)

    class << self
      # Período pela chave (PERIODS) ou por de/ate (AAAA-MM-DD, até 400 dias). Chave desconhecida
      # cai no padrão, a não ser com strict: true (MCP), que recusa.
      def period(key = nil, de: nil, ate: nil, now: Time.current, strict: false)
        return custom_period(de, ate, now) if de.present? || ate.present?
        raise Invalid, "periodo desconhecido. Use #{PERIODS.keys.join(', ')}, ou de e ate." if strict && key.present? && !PERIODS.key?(key)

        key = key.presence_in(PERIODS.keys) || DEFAULT_PERIOD
        today = now.to_date
        start, finish, bucket, step =
          case key
          when "hoje" then [ today.beginning_of_day, now, :hour, 1.day ]
          when "ontem" then [ (today - 1).beginning_of_day, (today - 1).end_of_day, :hour, 1.day ]
          when "7d" then [ (today - 6).beginning_of_day, now, :day, 7.days ]
          when "30d" then [ (today - 29).beginning_of_day, now, :day, 30.days ]
          when "este_mes" then [ today.beginning_of_month.beginning_of_day, now, :day, 1.month ]
          when "mes_passado" then [ today.prev_month.beginning_of_month.beginning_of_day, today.prev_month.end_of_month.end_of_day, :day, 1.month ]
          when "12m" then [ (today.beginning_of_month << 11).beginning_of_day, now, :month, 12.months ]
          end
        Period.new(key: key, label: PERIODS[key], range: start..finish, previous: previous_range(start, finish, step), bucket: bucket)
      end

      private

      def custom_period(de, ate, now)
        first = parse_date(de || ate)
        last = parse_date(ate || de)
        raise Invalid, "de precisa ser antes de ate." if first > last
        raise Invalid, "Intervalo de até #{MAX_DAYS} dias." if (last - first).to_i + 1 > MAX_DAYS

        start = first.beginning_of_day
        finish = [ last.end_of_day, now ].min
        days = (last - first).to_i + 1
        bucket = days <= 2 ? :hour : days <= 92 ? :day : :month
        label = "#{I18n.l(first)} a #{I18n.l(last)}"
        Period.new(key: "personalizado", label: label, range: start..finish, previous: previous_range(start, finish, nil), bucket: bucket)
      end

      def parse_date(value)
        Date.strptime(value.to_s, "%Y-%m-%d")
      rescue Date::Error
        raise Invalid, "Datas em AAAA-MM-DD (recebi #{value.to_s.inspect})."
      end

      # Os períodos prontos voltam pelo calendário, até a mesma hora: hoje × ontem, 7 dias × os 7
      # anteriores (os mesmos dias da semana), o mês × o mês anterior. O intervalo livre compara com
      # o de mesmo tamanho que termina onde ele começa.
      def previous_range(start, finish, step)
        return (start - step)..(finish - step) if step

        (start - (finish - start))...start
      end
    end

    attr_reader :period, :filters

    def initialize(period, filters = {})
      @period = period
      @filters = normalize_filters(filters.to_h.stringify_keys.slice(*FILTERS).compact_blank)
    end

    # Indicadores do período, do anterior, a variação e a série para o gráfico.
    def summary
      current = indicators(period.range)
      before = indicators(period.previous)
      { periodo: period_data, filtros: filters, indicadores: current, anterior: before,
        # Em %, menos a taxa de rejeição, que já é uma taxa: em pontos percentuais.
        variacao: current.to_h { |key, value| [ key, key == :taxa_rejeicao ? (value - before[key]).round(1) : variation(value, before[key]) ] },
        variacao_unidade: "% sobre o período anterior; taxa_rejeicao em pontos percentuais",
        serie: series, primeira_visita: SiteVisit.minimum(:started_at)&.to_date&.iso8601 }
    end

    def indicators(range)
      visitors, visits, pageviews, bounces, duration =
        visits(range).pick(Arel.sql("COUNT(DISTINCT visitor_hash)"), Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(pageviews_count), 0)"),
                           Arel.sql(bounce_sql), Arel.sql("COALESCE(AVG(duration_seconds), 0)"))
      { visitantes: visitors.to_i, visitas: visits.to_i, paginas_vistas: pageviews.to_i,
        paginas_por_visita: visits.to_i.positive? ? (pageviews.to_f / visits).round(2) : 0,
        taxa_rejeicao: visits.to_i.positive? ? (bounces.to_f * 100 / visits).round(1) : 0,
        duracao_media: duration.to_f.round }
    end

    # Visitantes, visitas e páginas vistas por hora, dia ou mês, com zero nos intervalos sem visita.
    def series
      format, ruby_format, step = { hour: [ "YYYY-MM-DD\"T\"HH24", "%Y-%m-%dT%H", 1.hour ], day: [ "YYYY-MM-DD", "%Y-%m-%d", 1.day ],
                                    month: [ "YYYY-MM", "%Y-%m", 1.month ] }.fetch(period.bucket)
      key = "to_char(date_trunc('#{period.bucket}', #{local_time('site_visits.started_at')}), '#{format}')"
      rows = visits.group(Arel.sql(key)).pluck(Arel.sql(key), Arel.sql("COUNT(DISTINCT visitor_hash)"), Arel.sql("COUNT(*)"),
                                               Arel.sql("COALESCE(SUM(pageviews_count), 0)")).to_h { |k, *values| [ k, values ] }
      cursor = period.range.begin.public_send(:"beginning_of_#{period.bucket}")
      points = []
      while cursor <= period.range.end
        visitors, visits, pageviews = rows.fetch(cursor.strftime(ruby_format), [ 0, 0, 0 ])
        points << { inicio: period.bucket == :hour ? cursor.iso8601 : cursor.to_date.iso8601,
                    visitantes: visitors.to_i, visitas: visits.to_i, paginas_vistas: pageviews.to_i }
        cursor += step
      end
      points
    end

    # Linhas agrupadas pela dimensão, ordenadas por visitas (dia da semana e hora em ordem natural),
    # mais o que ficou fora do limite em "outros".
    def by_dimension(dimension, limit: 25)
      raise Invalid, "dimensao desconhecida. Use #{DIMENSIONS.join(', ')}." unless DIMENSIONS.include?(dimension)

      total = indicators(period.range)[:visitas]
      rows = dimension_rows(dimension)
      rows = CHRONOLOGICAL.include?(dimension) ? rows.sort_by { |r| r[0].to_i } : rows.sort_by { |r| [ -r[2], -r[1], r[0].to_s ] }
      shown = rows.first(limit)
      rest = rows.drop(limit)
      { dimensao: dimension, periodo: period_data, filtros: filters, total_visitas: total,
        linhas: shown.map { |row| dimension_line(dimension, row, total) },
        outros: (rest.any? ? { grupos: rest.size, visitas: rest.sum { |r| r[2] }, paginas_vistas: rest.sum { |r| r[3] } } : nil) }
    end

    # Acessos de robôs e agentes de IA. Os falsos ficam fora dos totais, a não ser que o filtro de
    # verificação peça por eles. Traz junto as visitas de pessoas vindas de assistentes de IA.
    def ai_hits(group: "empresa", filters: {}, limit: 25)
      raise Invalid, "agrupar desconhecido. Use #{AI_GROUPS.join(', ')}." unless AI_GROUPS.include?(group)

      filters = ai_filters(filters)
      all = AiHit.where(occurred_at: period.range)
      all = all.where("LOWER(company) = ?", filters["empresa"].downcase) if filters["empresa"]
      all = all.where(kind: filters["tipo"]) if filters["tipo"]
      all = all.where(path: filters["pagina"]) if filters["pagina"]
      scope = filters["verificacao"] ? all.where(verification: filters["verificacao"]) : all.genuine

      expr = { "empresa" => "company", "agente" => "agent_name", "tipo" => "kind", "pagina" => "path",
               "dia" => "to_char(#{local_time('ai_hits.occurred_at')}, 'YYYY-MM-DD')" }.fetch(group)
      rows = scope.group(Arel.sql(expr)).pluck(Arel.sql(expr), Arel.sql("COUNT(*)"), Arel.sql("COUNT(*) FILTER (WHERE NOT blocked)"),
                                                Arel.sql("COUNT(*) FILTER (WHERE blocked)"))
      rows = group == "dia" ? rows.sort_by(&:first) : rows.sort_by { |r| [ -r[1], r[0].to_s ] }
      people = SiteVisit.where(started_at: period.range, channel: "ai_assistant")

      { periodo: period_data, agrupar: group, filtros: filters,
        total: scope.count, servidos: scope.served.count, bloqueados: scope.blocked.count,
        falsos: filters["verificacao"] ? nil : all.where(verification: "spoofed").count,
        por_tipo: labeled_counts(scope.group(:kind).count, AiHit::KIND_LABELS),
        por_verificacao: labeled_counts(scope.group(:verification).count, AiHit::VERIFICATION_LABELS),
        grupos: rows.first(limit).map { |value, total, served, blocked| { valor: value, rotulo: ai_label(group, value), acessos: total, servidos: served, bloqueados: blocked } },
        outros: (rows.size > limit ? { grupos: rows.size - limit, acessos: rows.drop(limit).sum { |r| r[1] } } : nil),
        visitas_de_assistentes_de_ia: { visitas: people.count, por_assistente: people.group(:ai_assistant).count.sort_by { |_, v| -v }.to_h } }
    end

    def period_data
      previous_end = period.previous.exclude_end? ? period.previous.end - 1.second : period.previous.end
      { chave: period.key, rotulo: period.label, de: period.range.begin.to_date.iso8601, ate: period.range.end.to_date.iso8601,
        agrupamento: BUCKETS.fetch(period.bucket),
        anterior: { de: period.previous.begin.to_date.iso8601, ate: previous_end.to_date.iso8601 } }
    end

    private

    def visits(range = period.range)
      scope = SiteVisit.where(started_at: range)
      scope = scope.where(channel: filters["canal"]) if filters["canal"]
      scope = scope.where(referrer_host: filters["origem"] == "direto" ? nil : filters["origem"]) if filters["origem"]
      %w[utm_source utm_medium utm_campaign].each { |key| scope = scope.where(key => filters[key]) if filters[key] }
      scope = scope.where(entry_path: filters["pagina_entrada"]) if filters["pagina_entrada"]
      scope = scope.where(device_type: filters["dispositivo"]) if filters["dispositivo"]
      scope = scope.where(id: SitePageview.where(path: filters["pagina"]).select(:site_visit_id)) if filters["pagina"]
      scope
    end

    def dimension_rows(dimension)
      if dimension == "pagina"
        bounced = "COUNT(DISTINCT CASE WHEN site_visits.pageviews_count = 1 AND site_visits.duration_seconds < #{BOUNCE_SECONDS} THEN site_visits.id END)"
        SitePageview.joins(:site_visit).merge(visits).group("site_pageviews.path")
                    .pluck(Arel.sql("site_pageviews.path"), Arel.sql("COUNT(DISTINCT site_visits.visitor_hash)"), Arel.sql("COUNT(DISTINCT site_pageviews.site_visit_id)"),
                           Arel.sql("COUNT(*)"), Arel.sql(bounced), Arel.sql("AVG(site_pageviews.duration_seconds)"))
      else
        expr = dimension_sql(dimension)
        scope = dimension == "assistente_ia" ? visits.where.not(ai_assistant: nil) : visits
        scope.group(Arel.sql(expr)).pluck(Arel.sql(expr), Arel.sql("COUNT(DISTINCT visitor_hash)"), Arel.sql("COUNT(*)"),
                                          Arel.sql("COALESCE(SUM(pageviews_count), 0)"), Arel.sql(bounce_sql), Arel.sql("AVG(duration_seconds)"))
      end.map { |value, visitors, visits, pageviews, bounces, duration| [ value, visitors.to_i, visits.to_i, pageviews.to_i, bounces.to_i, duration ] }
    end

    def dimension_sql(dimension)
      { "canal" => "site_visits.channel", "assistente_ia" => "site_visits.ai_assistant",
        "origem" => "COALESCE(site_visits.referrer_host, 'direto')",
        "utm_source" => "site_visits.utm_source", "utm_medium" => "site_visits.utm_medium", "utm_campaign" => "site_visits.utm_campaign",
        "pagina_entrada" => "site_visits.entry_path", "pagina_saida" => "site_visits.exit_path",
        "dispositivo" => "site_visits.device_type", "navegador" => "site_visits.browser", "sistema" => "site_visits.os",
        "dia_da_semana" => "EXTRACT(DOW FROM #{local_time('site_visits.started_at')})::int",
        "hora" => "EXTRACT(HOUR FROM #{local_time('site_visits.started_at')})::int" }.fetch(dimension)
    end

    def dimension_line(dimension, (value, visitors, visits, pageviews, bounces, duration), total)
      hidden = HIDDEN_BELOW_MIN.include?(dimension) && !value.nil? && visitors < MIN_VISITORS
      line = { valor: hidden ? nil : value, rotulo: hidden ? "(oculto: menos de #{MIN_VISITORS} visitantes)" : dimension_label(dimension, value),
               visitantes: visitors, visitas: visits, paginas_vistas: pageviews,
               percentual: total.positive? ? (visits * 100.0 / total).round(1) : 0,
               taxa_rejeicao: visits.positive? ? (bounces * 100.0 / visits).round(1) : 0,
               duracao_media: duration.to_f.round }
      line[:oculto] = true if hidden
      line
    end

    def dimension_label(dimension, value)
      return "(sem valor)" if value.nil?

      case dimension
      when "canal" then SiteVisit::CHANNEL_LABELS.fetch(value, value)
      when "dispositivo" then SiteVisit::DEVICE_TYPE_LABELS.fetch(value, value)
      when "origem" then value == "direto" ? "Direto" : value
      when "dia_da_semana" then WEEKDAYS[value.to_i]
      when "hora" then format("%02dh", value.to_i)
      else value
      end
    end

    def ai_label(group, value)
      case group
      when "tipo" then AiHit::KIND_LABELS.fetch(value, value)
      else value
      end
    end

    def labeled_counts(counts, labels)
      counts.sort_by { |_, v| -v }.map { |key, count| { valor: key, rotulo: labels.fetch(key, key), acessos: count } }
    end

    def normalize_filters(raw)
      raw.each_with_object({}) do |(key, value), result|
        value = value.to_s.strip
        result[key] =
          case key
          when "canal" then value.presence_in(SiteVisit::CHANNEL_LABELS.keys) || raise(Invalid, "canal desconhecido. Use #{SiteVisit::CHANNEL_LABELS.keys.join(', ')}.")
          when "dispositivo" then value.presence_in(SiteVisit::DEVICE_TYPE_LABELS.keys) || raise(Invalid, "dispositivo desconhecido. Use #{SiteVisit::DEVICE_TYPE_LABELS.keys.join(', ')}.")
          when "origem" then value.downcase.delete_prefix("www.")
          when "pagina", "pagina_entrada" then normalize_path(value)
          else value
          end
      end
    end

    def ai_filters(raw)
      raw.to_h.stringify_keys.slice(*AI_FILTERS).compact_blank.to_h do |key, value|
        value = value.to_s.strip
        value =
          case key
          when "tipo" then value.presence_in(AiHit::KIND_LABELS.keys) || raise(Invalid, "tipo desconhecido. Use #{AiHit::KIND_LABELS.keys.join(', ')}.")
          when "verificacao" then value.presence_in(AiHit::VERIFICATION_LABELS.keys) || raise(Invalid, "verificacao desconhecida. Use #{AiHit::VERIFICATION_LABELS.keys.join(', ')}.")
          when "pagina" then normalize_path(value)
          else value
          end
        [ key, value ]
      end
    end

    # Como o Tracker grava: com a barra inicial e sem a barra no fim.
    def normalize_path(value)
      path = value.start_with?("/") ? value : "/#{value}"
      path.length > 1 ? path.chomp("/") : path
    end

    def bounce_sql
      "COUNT(*) FILTER (WHERE pageviews_count = 1 AND duration_seconds < #{BOUNCE_SECONDS})"
    end

    # Os timestamps ficam em UTC (sem fuso); dia e hora são os do fuso do app.
    def local_time(column)
      "((#{column} AT TIME ZONE 'UTC') AT TIME ZONE '#{Time.zone.tzinfo.identifier}')"
    end

    def variation(current, previous)
      return nil unless previous.to_f.positive?

      ((current - previous) * 100.0 / previous).round(1)
    end
  end
end
