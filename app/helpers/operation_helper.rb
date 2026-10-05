module OperationHelper
  PROJECT_TONES = { "planning" => "mute", "in_progress" => "info", "paused" => "warn", "waiting_client" => "warn", "done" => "good", "cancelled" => "mute" }.freeze
  TASK_TONES = { "backlog" => "mute", "todo" => "mute", "in_progress" => "info", "review" => "warn", "done" => "good" }.freeze
  TICKET_TONES = { "open" => "info", "analyzing" => "info", "in_progress" => "warn", "waiting_client" => "warn", "resolved" => "good", "closed" => "mute" }.freeze
  PRIORITY_TONES = { "low" => "mute", "normal" => "info", "high" => "warn", "urgent" => "crit", "critical" => "crit" }.freeze

  # 210 → "3h30"; com pad: true, 240 → "4h00" (colunas de duração).
  def hours_br(minutes, pad: false)
    TimeEntry.format_minutes(minutes, pad: pad)
  end

  # Tempo decorrido em texto: "45 min", "5h 20min", "2,4 dias".
  def duration_text(minutes)
    minutes = minutes.to_i
    return "#{minutes} min" if minutes < 60
    return "#{number_with_precision(minutes / 1440.0, precision: 1, separator: ',', strip_insignificant_zeros: true)} dias" if minutes >= 1440

    hours, mins = minutes.divmod(60)
    mins.zero? ? "#{hours}h" : "#{hours}h #{mins}min"
  end

  def project_badge(project)
    status_badge(project.status_label, PROJECT_TONES[project.status])
  end

  def task_badge(task)
    status_badge(task.status_label, TASK_TONES[task.status])
  end

  def ticket_badge(ticket)
    status_badge(ticket.status_label, TICKET_TONES[ticket.status])
  end

  def priority_badge(record)
    tag.span(record.priority_label, class: "badge b-#{PRIORITY_TONES[record.priority]}#{' dot-l' if record.priority.in?(%w[critical])}")
  end

  def progress_bar(percent, label:, tone: nil, size: nil)
    tag.div(class: [ "progress", tone, size ].compact.join(" "), role: "progressbar", "aria-valuenow": percent,
            "aria-valuemin": 0, "aria-valuemax": 100, "aria-label": label) { tag.i(style: "width:#{percent.to_i.clamp(0, 100)}%") }
  end

  # "18h / 24h" das tarefas: registradas × estimativa, em vermelho quando passa da estimativa.
  def logged_vs_estimate(task, logged)
    text = "#{hours_br(logged)} / #{task.estimated_minutes ? hours_br(task.estimated_minutes) : '—'}"
    tag.span(text, class: ("over" if task.over_estimate?(logged)))
  end

  # Barras horizontais "por cliente"/"por pessoa": [[rótulo, minutos], ...].
  def hour_bars(rows, max: nil, alt: [])
    max ||= rows.map(&:last).max.to_i
    safe_join(rows.map do |label, minutes|
      width = max.positive? ? (minutes * 100.0 / max).round.clamp(0, 100) : 0
      tag.div(class: "hbar") do
        safe_join([ label.is_a?(String) ? tag.span(label) : label,
                    tag.div(class: "track") { tag.div(class: "fill#{' alt' if alt.include?(label)}", style: "width:#{width}%") },
                    tag.span(hours_br(minutes), class: "val") ])
      end
    end)
  end
end
