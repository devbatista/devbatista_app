# Gráficos simples com as classes do design system (.bars, .axis, .hbars). Os valores aparecem
# na dica de cada barra, no rótulo da última e no aria-label, então a cor nunca é a única pista.
module ChartsHelper
  # Barras verticais: rows = [[Date (mês), centavos]]; a última fica em destaque e com rótulo.
  def month_bar_chart(rows, title:)
    max = [ rows.map(&:last).max.to_i, 1 ].max
    summary = rows.map { |m, v| "#{month_abbr(m)} #{brl(v)}" }.join(", ")
    bars = tag.div(class: "bars", role: "img", "aria-label": "#{title}: #{summary}") do
      safe_join(rows.each_with_index.map do |(month, value), i|
        last = i == rows.size - 1
        height = value.positive? ? (value * 88.0 / max).round.clamp(1, 88) : 0
        tag.div(class: "col", title: "#{month_abbr(month)}: #{brl(value)}") do
          safe_join([ (tag.span(thousands(value), class: "lbl") if last), tag.div(class: "bar#{' cur' if last}", style: "height:#{height}%") ].compact)
        end
      end)
    end
    safe_join([ bars, month_axis(rows.map(&:first)) ])
  end

  # Linha com área (evolução do MRR).
  def month_line_chart(rows, title:)
    values = rows.map(&:last)
    max = [ values.max.to_i, 1 ].max
    step = rows.size > 1 ? 300.0 / (rows.size - 1) : 0
    points = values.each_with_index.map { |v, i| "#{(i * step).round(1)},#{(146 - v * 120.0 / max).round(1)}" }
    svg = tag.svg(width: "100%", height: 150, viewBox: "0 0 300 150", preserveAspectRatio: "none", role: "img",
                  "aria-label": "#{title}: #{rows.map { |m, v| "#{month_abbr(m)} #{brl(v)}" }.join(', ')}") do
      safe_join([
        tag.line(x1: 0, y1: 50, x2: 300, y2: 50, style: "stroke:var(--rule)", "vector-effect": "non-scaling-stroke"),
        tag.line(x1: 0, y1: 100, x2: 300, y2: 100, style: "stroke:var(--rule)", "vector-effect": "non-scaling-stroke"),
        tag.polygon(points: "0,150 #{points.join(' ')} 300,150", style: "fill:var(--cyan);fill-opacity:.1"),
        tag.polyline(points: points.join(" "), fill: "none", style: "stroke:var(--cyan)", "stroke-width": 2, "vector-effect": "non-scaling-stroke", "stroke-linejoin": "round")
      ])
    end
    box = tag.div(style: "position:relative;height:150px;border-bottom:1px solid var(--border-strong)") do
      safe_join([ svg, tag.span(thousands(values.last.to_i), style: "position:absolute;right:0;top:4px;font-size:13px;font-weight:700;color:var(--white)"),
                  tag.span(thousands(values.first.to_i), style: "position:absolute;left:0;top:calc(#{((146 - values.first.to_i * 120.0 / max) / 1.5).round(1)}% + 6px);font-size:12px;color:var(--muted)") ])
    end
    safe_join([ box, month_axis(rows.map(&:first)) ])
  end

  # Barras horizontais com os maiores e o resto somado em "Demais".
  #   rows = [[rótulo ou link, centavos]]
  def ranked_hbars(rows, top: 5, wide: false, value: ->(v) { thousands(v) }, tip: ->(v) { brl(v) })
    rows = rows.reject { |_, v| v.to_f <= 0 }
    shown = rows.first(top)
    rest = rows.drop(top)
    if rest.size == 1
      shown += rest
    elsif rest.any?
      shown << [ "Demais #{rest.size}", rest.sum(&:last), :alt ]
    end
    max = [ shown.map { |r| r[1] }.max.to_f, 1 ].max
    tag.div(class: "hbars") do
      safe_join(shown.map do |label, cents, alt|
        tag.div(class: "hbar#{' wide' if wide}", title: "#{strip_tags(label.to_s)}: #{tip.call(cents)}") do
          safe_join([ label.is_a?(String) ? tag.span(label) : label,
                      tag.div(class: "track") { tag.div(class: "fill#{' alt' if alt}", style: "width:#{(cents * 100.0 / max).round}%") },
                      tag.span(value.call(cents), class: "val") ])
        end
      end)
    end
  end

  def month_abbr(date)
    l(date, format: "%b").capitalize.delete(".")
  end

  def percent_br(value, precision: 1)
    value.nil? ? "—" : "#{number_with_precision(value, precision: precision, separator: ',', strip_insignificant_zeros: true)}%"
  end

  # Variação percentual com sinal, para os badges de comparação.
  def variation_badge(current, previous, inverse: false)
    return unless previous.to_i.positive?

    pct = ((current - previous) * 100.0 / previous).round(1)
    good = inverse ? pct <= 0 : pct >= 0
    status_badge("#{pct.positive? ? '+' : ('−' if pct.negative?)}#{percent_br(pct.abs)}", good ? "good" : "crit")
  end

  # Diferença em pontos percentuais (margem, churn, conversão).
  def points_badge(current, previous, inverse: false)
    return if current.nil? || previous.nil?

    diff = (current - previous).round(1)
    good = inverse ? diff <= 0 : diff >= 0
    status_badge("#{diff.positive? ? '+' : ('−' if diff.negative?)}#{number_with_precision(diff.abs, precision: 1, separator: ',')} p.p.", good ? "good" : "crit")
  end

  private

  def month_axis(months)
    tag.div(class: "axis") { safe_join(months.map { |m| tag.span(month_abbr(m)) }) }
  end
end
