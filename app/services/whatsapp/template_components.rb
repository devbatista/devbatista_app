module Whatsapp
  # Monta os components do envio de um template na Cloud API.
  #
  #   TemplateComponents.build(body: [ "Beatriz", "Novo site" ])                 # {{1}}, {{2}}
  #   TemplateComponents.build(body: { "nome" => "Beatriz" })                    # parâmetros nomeados
  #   TemplateComponents.build(header: [ "P-2026-029" ], url_buttons: { 0 => "p/P-2026-029" })
  #   TemplateComponents.build(header: { document: { id: "123", filename: "proposta.pdf" } })
  #
  # O sufixo do botão de URL vai codificado (percent-encoding) segmento a segmento: as barras
  # ficam, para que "p/P-2026-029" continue apontando para /p/P-2026-029.
  module TemplateComponents
    MEDIA = %w[image video document].freeze

    def self.build(body: [], header: nil, url_buttons: {})
      components = []
      components << { type: "header", parameters: header_parameters(header) } if header.present?
      components << { type: "body", parameters: text_parameters(body) } if body.present?
      url_buttons.each do |index, value|
        components << { type: "button", sub_type: "url", index: index.to_s, parameters: [ { type: "text", text: url_suffix(value) } ] }
      end
      components
    end

    def self.url_suffix(value)
      value.to_s.split("/", -1).map { |segment| ERB::Util.url_encode(segment) }.join("/")
    end

    def self.text_parameters(values)
      return values.map { |name, text| { type: "text", parameter_name: name.to_s, text: text.to_s } } if values.is_a?(Hash)

      Array(values).map { |text| { type: "text", text: text.to_s } }
    end

    def self.header_parameters(header)
      media = header.is_a?(Hash) ? header.transform_keys(&:to_s).slice(*MEDIA).first : nil
      return text_parameters(header) unless media

      type, content = media
      [ { type: type, type.to_sym => content } ]
    end
  end
end
