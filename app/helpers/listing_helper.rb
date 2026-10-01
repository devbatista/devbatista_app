module ListingHelper
  # Tom do badge por status, igual em todos os models.
  STATUS_TONES = {
    "active" => "good", "prospect" => "info", "inactive" => "mute",
    "draft" => "mute", "expiring" => "warn", "ended" => "mute", "cancelled" => "crit",
    "suspended" => "warn"
  }.freeze

  def status_badge_for(record, attribute = :status)
    value = record.public_send(attribute)
    status_badge(record.public_send("#{attribute}_label"), STATUS_TONES.fetch(value, "mute"))
  end

  # Filtro de status em abas (.seg) que recarrega a lista no servidor.
  #   status_filter :status, [["todos", "Todas", 19], ["active", "Ativo", 14]]
  def status_filter(param, options, label: "Filtrar por status")
    current = params[param].presence || "todos"
    tag.nav(class: "seg", "aria-label": label) do
      safe_join(options.map do |value, text, count|
        query = request.query_parameters.except("page").merge(param.to_s => (value == "todos" ? nil : value)).compact
        link_to url_for(query), class: ("on" if current == value), "aria-current": (current == value ? "true" : nil) do
          safe_join([ text, (tag.span(count, class: "n") if count) ].compact, " ")
        end
      end)
    end
  end

  # Mantém os filtros atuais como campos ocultos num formulário GET.
  def preserved_filters(*except)
    safe_join(request.query_parameters.except("page", *except.map(&:to_s)).map { |key, value| hidden_field_tag(key, value, id: nil) })
  end

  # Link que abre o formulário na gaveta lateral (Turbo Frame "drawer-frame").
  def drawer_link_to(name = nil, path = nil, **options, &block)
    path, name = name, capture(&block) if block
    data = (options.delete(:data) || {}).merge(turbo_frame: "drawer-frame", open: "drawer")
    link_to(name, path, **options, data: data)
  end

  def search_field(placeholder:, label:, param: :q)
    tag.label(class: "search-field") do
      safe_join([ tag.span(label, class: "sr-only"), icon(:search, size: 16, stroke: 1.8),
                  search_field_tag(param, params[param], class: "input", placeholder: placeholder, id: nil) ])
    end
  end
end
