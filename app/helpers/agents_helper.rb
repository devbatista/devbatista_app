# Escritório de agentes de IA (docs/specs/escritorio-agentes): chips de status e de decisão.
module AgentsHelper
  STATUS_TONES = { "working" => "info", "idle" => "mute", "awaiting_approval" => "warn", "done" => "good", "error" => "crit" }.freeze
  DECISION_TONES = { "pending" => "warn", "approved" => "good", "rejected" => "crit" }.freeze

  def agent_status_badge(status)
    tag.span(AgentEvent::STATUS_LABELS.fetch(status), class: "badge b-#{STATUS_TONES.fetch(status)} dot-l")
  end

  def agent_decision_badge(event)
    status_badge(event.decision_label, DECISION_TONES.fetch(event.decision)) if event.decision
  end

  # "agora", "há 5 min", "há 2 h", "ontem 18:40" (time_ago_in_words diria "aproximadamente 2 horas").
  def agent_time(time)
    return "—" unless time

    elapsed = Time.current - time
    return "agora" if elapsed < 1.minute
    return "há #{(elapsed / 1.minute).floor} min" if elapsed < 1.hour
    return "há #{(elapsed / 1.hour).floor} h" if elapsed < 12.hours

    time.to_date == Date.yesterday ? "ontem #{l(time, format: '%H:%M')}" : datetime_br(time)
  end
end
