# Enum com rótulos em português para a interface.
#
#   labeled_enum :status, active: "Ativo", inactive: "Inativo"
#
# Gera o enum do Rails (valores em inglês no banco), a constante STATUS_LABELS,
# o método de instância status_label e options_for_status para selects.
module LabeledEnums
  extend ActiveSupport::Concern

  class_methods do
    ENUM_OPTIONS = %i[prefix suffix default scopes].freeze

    # Aceita os rótulos como keywords ou, quando há opções do enum, como hash:
    #   labeled_enum :kind, recurring: "Recorrente"
    #   labeled_enum :renewal, { none: "Sem renovação" }, prefix: true
    def labeled_enum(attribute, labels = nil, **options)
      enum_options = options.slice(*ENUM_OPTIONS)
      labels = (labels || options.except(*ENUM_OPTIONS)).transform_keys(&:to_s).freeze
      const_set("#{attribute.to_s.upcase}_LABELS", labels)
      enum attribute, labels.keys.index_with(&:itself), validate: true, **enum_options

      define_method("#{attribute}_label") { labels[public_send(attribute)] }
      define_singleton_method("options_for_#{attribute}") { labels.map { |value, label| [ label, value ] } }
    end
  end
end
