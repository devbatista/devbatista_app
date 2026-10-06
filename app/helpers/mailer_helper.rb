# Blocos dos e-mails, com estilo inline (clientes de e-mail ignoram CSS externo).
# As cores seguem os tokens do design system (docs/design/DESIGN-SYSTEM.md).
#
#   <%= mail_label "Contratos vencendo" %>
#   <%= mail_title "Contrato #104 vence em 30 dias" %>
#   <%= mail_text "Olá, Ana." %>
#   <%= mail_button "Abrir no sistema", url %>
#   <%= mail_note { "Você recebe este e-mail porque…" } %>
module MailerHelper
  FONT = "Montserrat, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif".freeze

  COLORS = {
    white: "#ffffff", text: "#cbd5e1", muted: "#94a3b8", faint: "#64748b",
    cyan: "#22d3ee", bg: "#0b1120", rule: "#172033"
  }.freeze

  BADGES = {
    "info" => [ "#67e8f9", "rgba(34,211,238,.1)", "rgba(22,78,99,.6)" ],
    "good" => [ "#6ee7b7", "rgba(16,185,129,.1)", "rgba(6,95,70,.6)" ],
    "warn" => [ "#fcd34d", "rgba(245,158,11,.1)", "rgba(120,53,15,.6)" ],
    "crit" => [ "#fca5a5", "rgba(239,68,68,.1)", "rgba(127,29,29,.6)" ]
  }.freeze

  # Rótulo ciano acima do título: a área ou o tipo do e-mail.
  def mail_label(text)
    tag.p(text, style: "margin:0 0 8px;font-family:#{FONT};font-size:12px;font-weight:600;letter-spacing:.15em;" \
                       "text-transform:uppercase;color:#{COLORS[:cyan]}")
  end

  def mail_title(text)
    tag.h1(text, style: "margin:0 0 16px;font-family:#{FONT};font-size:22px;line-height:1.3;font-weight:700;" \
                        "letter-spacing:-.01em;color:#{COLORS[:white]}")
  end

  def mail_text(text = nil, &block)
    tag.p(text || capture(&block), style: "margin:0 0 16px;font-family:#{FONT};font-size:14px;line-height:1.6;color:#{COLORS[:text]}")
  end

  # Status com texto, nunca só a cor (níveis: info, good, warn, crit).
  def mail_badge(text, level = "info")
    color, background, border = BADGES.fetch(level.to_s, BADGES["info"])
    tag.p(style: "margin:0 0 16px") do
      tag.span(text, style: "display:inline-block;padding:3px 10px;border-radius:999px;border:1px solid #{border};" \
                            "background:#{background};font-family:#{FONT};font-size:12px;font-weight:600;color:#{color}")
    end
  end

  # Botão em tabela, para funcionar também no Outlook.
  def mail_button(text, url)
    tag.table(role: "presentation", cellpadding: 0, cellspacing: 0, border: 0, style: "margin:8px 0 24px") do
      tag.tr do
        tag.td(bgcolor: COLORS[:cyan], style: "border-radius:8px;background:#{COLORS[:cyan]}") do
          link_to(text, url, style: "display:inline-block;padding:12px 22px;font-family:#{FONT};font-size:14px;font-weight:600;" \
                                    "color:#{COLORS[:bg]};text-decoration:none;border-radius:8px")
        end
      end
    end
  end

  # Link por extenso, para quando o botão não abre. Vem logo depois de um mail_note.
  def mail_link_fallback(url)
    mail_note(rule: false) do
      safe_join([ "Se o botão não funcionar, copie e cole este endereço no navegador:", tag.br,
                  link_to(url, url, style: "color:#{COLORS[:cyan]};word-break:break-all") ])
    end
  end

  # Texto secundário no fim do conteúdo; o primeiro abre com uma linha divisória.
  def mail_note(text = nil, rule: true, &block)
    spacing = rule ? "padding-top:16px;border-top:1px solid #{COLORS[:rule]}" : "padding-top:8px"
    tag.p(text || capture(&block), style: "margin:0;#{spacing};font-family:#{FONT};font-size:12px;line-height:1.6;color:#{COLORS[:muted]}")
  end

  # "2 horas", "30 minutos" (distance_of_time_in_words diria "aproximadamente 2 horas").
  def mail_duration(duration)
    return pluralize(duration.in_hours.to_i, "hora") if (duration % 1.hour).zero?

    pluralize(duration.in_minutes.to_i, "minuto")
  end
end
