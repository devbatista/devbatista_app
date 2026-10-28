module Whatsapp
  # Formulário de template (docs/specs/whatsapp, Fase 5): valida os campos pelas regras da Meta e
  # monta os components no formato da Graph API, separado da tela.
  #
  #   builder = Whatsapp::TemplateBuilder.new(name: "lembrete_proposta", category: "utility",
  #                                          body: "Olá, {{1}}. A proposta vence amanhã.", body_examples: [ "Beatriz" ])
  #   builder.valid? && builder.components
  #   # => [ { "type" => "BODY", "text" => "Olá, {{1}}. …", "example" => { "body_text" => [ [ "Beatriz" ] ] } } ]
  #
  # Variáveis posicionais ({{1}}, {{2}}…), em sequência e com um exemplo cada. Os botões chegam como
  # hashes { type: quick_reply | url | phone, text, url, url_example, phone }.
  class TemplateBuilder
    include ActiveModel::Model
    include ActiveModel::Attributes

    HEADER_TYPES = { "" => "Nenhum", "text" => "Texto", "image" => "Imagem", "document" => "Documento", "video" => "Vídeo" }.freeze
    MEDIA_HEADERS = %w[image document video].freeze
    # Formatos aceitos no exemplo da mídia do cabeçalho.
    HEADER_MIME_TYPES = { "image" => %w[image/jpeg image/png], "document" => %w[application/pdf], "video" => %w[video/mp4 video/3gpp] }.freeze
    BUTTON_TYPES = { "quick_reply" => "Resposta rápida", "url" => "Acessar site", "phone" => "Ligar" }.freeze
    LIMITS = { body: 1024, header: 60, footer: 60, button_text: 25, buttons: 10, url_buttons: 2, phone_buttons: 1, url: 2000 }.freeze
    NAME = /\A[a-z0-9_]{1,512}\z/
    VARIABLE = /\{\{(.*?)\}\}/
    URL = %r{\Ahttps?://[^\s/$.?#].[^\s]*\z}i
    PHONE = /\A\+?\d{8,20}\z/

    attribute :name, :string
    attribute :language, :string, default: "pt_BR"
    attribute :category, :string, default: "utility"
    attribute :header_type, :string, default: ""
    attribute :header_text, :string
    attribute :header_example, :string
    attribute :header_handle, :string
    attribute :body, :string
    attribute :body_examples, default: -> { [] }
    attribute :footer, :string
    attribute :buttons, default: -> { [] }

    validate :check_identity, :check_header, :check_body, :check_footer, :check_buttons

    # Campos do formulário a partir dos components gravados (para editar).
    def self.from_template(template)
      header = template.component("HEADER") || {}
      body = template.component("BODY") || {}
      new(name: template.name, language: template.language, category: template.category,
          header_type: header["format"].to_s.downcase, header_text: header["text"],
          header_example: header.dig("example", "header_text", 0), header_handle: header.dig("example", "header_handle", 0),
          body: body["text"], body_examples: Array(body.dig("example", "body_text", 0)), footer: template.component("FOOTER")&.dig("text"),
          buttons: Array(template.component("BUTTONS")&.dig("buttons")).map { |button| button_from_meta(button) })
    end

    def self.button_from_meta(button)
      case button["type"]
      when "URL" then { "type" => "url", "text" => button["text"], "url" => button["url"], "url_example" => Array(button["example"]).first }
      when "PHONE_NUMBER" then { "type" => "phone", "text" => button["text"], "phone" => button["phone_number"] }
      else { "type" => "quick_reply", "text" => button["text"] }
      end
    end

    def body_examples=(values)
      super(Array(values).map { |value| value.to_s.strip })
    end

    # Linhas vazias (sem texto nem valor) somem; o telefone fica só com + e dígitos.
    def buttons=(values)
      list = values.respond_to?(:values) && !values.is_a?(Array) ? values.values : Array(values)
      super(list.filter_map do |button|
        button = button.to_h.stringify_keys.transform_values { |value| value.to_s.strip }
        next if button.values_at("text", "url", "phone").all?(&:blank?)

        button["phone"] = button["phone"].gsub(/[^\d+]/, "") if button["phone"].present?
        button.slice("type", "text", "url", "url_example", "phone")
      end)
    end

    def media_header?
      MEDIA_HEADERS.include?(header_type)
    end

    def body_variables
      numbers(body)
    end

    # Components da Graph API. Respostas rápidas primeiro: a Meta pede os botões agrupados por tipo.
    def components
      list = []
      list << header_component if header_type.present?
      body_component = { "type" => "BODY", "text" => body.to_s.strip }
      body_component["example"] = { "body_text" => [ body_examples.first(body_variables.size) ] } if body_variables.any?
      list << body_component
      list << { "type" => "FOOTER", "text" => footer.strip } if footer.present?
      list << { "type" => "BUTTONS", "buttons" => buttons.sort_by { |b| b["type"] == "quick_reply" ? 0 : 1 }.map { |b| button_component(b) } } if buttons.any?
      list
    end

    def template_attributes
      { name: name, language: language, category: category, components: components }
    end

    # Envia o arquivo de exemplo do cabeçalho de mídia e guarda o handle. O handle volta no
    # formulário (campo oculto), para não precisar escolher o arquivo de novo se outro campo der erro.
    def upload_sample(file, client)
      allowed = HEADER_MIME_TYPES.fetch(header_type)
      unless allowed.include?(file.content_type)
        raise Error, "O exemplo de #{HEADER_TYPES[header_type].downcase} precisa ser #{allowed.map { |t| t.split('/').last.upcase }.to_sentence(two_words_connector: ' ou ', last_word_connector: ' ou ')}."
      end

      self.header_handle = client.upload_template_sample(file, filename: file.original_filename, mime_type: file.content_type)
    end

    private

    def header_component
      return { "type" => "HEADER", "format" => header_type.upcase, "example" => { "header_handle" => [ header_handle ] } } if media_header?

      component = { "type" => "HEADER", "format" => "TEXT", "text" => header_text.to_s.strip }
      component["example"] = { "header_text" => [ header_example.to_s.strip ] } if numbers(header_text).any?
      component
    end

    def button_component(button)
      case button["type"]
      when "url"
        component = { "type" => "URL", "text" => button["text"], "url" => button["url"] }
        component["example"] = [ button["url_example"] ] if button["url"].to_s.match?(VARIABLE)
        component
      when "phone" then { "type" => "PHONE_NUMBER", "text" => button["text"], "phone_number" => button["phone"] }
      else { "type" => "QUICK_REPLY", "text" => button["text"] }
      end
    end

    def numbers(text)
      text.to_s.scan(VARIABLE).flatten.map(&:strip).select { |name| name.match?(/\A\d+\z/) }.map(&:to_i).uniq.sort
    end

    # ---------- validações ----------

    def check_identity
      errors.add(:base, "O nome usa só letras minúsculas, números e _ (sublinhado).") unless name.to_s.match?(NAME)
      errors.add(:base, "Escolha o idioma: português, inglês ou espanhol.") unless WhatsappTemplate::LANGUAGES.key?(language)
      errors.add(:base, "Escolha a categoria: Marketing ou Utilidade.") unless WhatsappTemplate::CREATABLE_CATEGORIES.include?(category)
    end

    def check_header
      return errors.add(:base, "Tipo de cabeçalho inválido.") unless HEADER_TYPES.key?(header_type.to_s)
      return errors.add(:base, "Envie um arquivo de exemplo para o cabeçalho de #{HEADER_TYPES[header_type].downcase}.") if media_header? && header_handle.blank?
      return unless header_type == "text"

      text = header_text.to_s.strip
      return errors.add(:base, "Escreva o texto do cabeçalho.") if text.empty?

      errors.add(:base, "O cabeçalho tem até #{LIMITS[:header]} caracteres.") if text.length > LIMITS[:header]
      names = text.scan(VARIABLE).flatten.map(&:strip)
      return if names.empty?
      return errors.add(:base, "O cabeçalho aceita só uma variável, {{1}}.") unless names.uniq == [ "1" ]

      check_variable_placement(text, "O cabeçalho", edges: false)
      errors.add(:base, "Informe o exemplo da variável do cabeçalho.") if header_example.blank?
    end

    def check_body
      text = body.to_s.strip
      return errors.add(:base, "Escreva o corpo da mensagem.") if text.empty?

      errors.add(:base, "O corpo tem até #{LIMITS[:body]} caracteres.") if text.length > LIMITS[:body]
      names = text.scan(VARIABLE).flatten.map(&:strip)
      return errors.add(:base, "Use variáveis numeradas: {{1}}, {{2}}…") if names.any? { |n| !n.match?(/\A\d+\z/) }

      vars = body_variables
      errors.add(:base, "As variáveis do corpo precisam estar em sequência, sem pular números ({{1}}, {{2}}…).") if vars.any? && vars != (1..vars.max).to_a
      check_variable_placement(text, "O corpo")
      missing = vars.select { |n| body_examples[n - 1].blank? }
      errors.add(:base, "Informe o exemplo de #{missing.map { |n| "{{#{n}}}" }.to_sentence}.") if missing.any?
    end

    def check_variable_placement(text, label, edges: true)
      errors.add(:base, "#{label} não pode começar nem terminar com uma variável.") if edges && (text.start_with?("{{") || text.end_with?("}}"))
      errors.add(:base, "#{label} tem variáveis seguidas, sem texto entre elas.") if text.match?(/\}\}\s*\{\{/)
    end

    def check_footer
      return if footer.blank?

      errors.add(:base, "O rodapé tem até #{LIMITS[:footer]} caracteres.") if footer.strip.length > LIMITS[:footer]
      errors.add(:base, "O rodapé não aceita variáveis.") if footer.match?(VARIABLE)
    end

    def check_buttons
      errors.add(:base, "São até #{LIMITS[:buttons]} botões.") if buttons.size > LIMITS[:buttons]
      errors.add(:base, "São até #{LIMITS[:url_buttons]} botões de link.") if buttons.count { |b| b["type"] == "url" } > LIMITS[:url_buttons]
      errors.add(:base, "É só #{LIMITS[:phone_buttons]} botão de telefone.") if buttons.count { |b| b["type"] == "phone" } > LIMITS[:phone_buttons]
      buttons.each.with_index(1) { |button, index| check_button(button, "Botão #{index}") }
    end

    def check_button(button, label)
      return errors.add(:base, "#{label}: tipo inválido.") unless BUTTON_TYPES.key?(button["type"])

      text = button["text"].to_s
      errors.add(:base, "#{label}: escreva o texto do botão.") if text.empty?
      errors.add(:base, "#{label}: o texto tem até #{LIMITS[:button_text]} caracteres.") if text.length > LIMITS[:button_text]
      check_url_button(button, label) if button["type"] == "url"
      errors.add(:base, "#{label}: informe o telefone com DDI, como +5511999998888.") if button["type"] == "phone" && !button["phone"].to_s.match?(PHONE)
    end

    def check_url_button(button, label)
      url = button["url"].to_s
      return errors.add(:base, "#{label}: informe o link, começando com https://.") unless url.match?(URL) && url.length <= LIMITS[:url]

      names = url.scan(VARIABLE).flatten.map(&:strip)
      return if names.empty?
      return errors.add(:base, "#{label}: o link aceita só uma variável, {{1}}, no fim.") unless names == [ "1" ] && url.end_with?("}}")

      errors.add(:base, "#{label}: informe um exemplo do link completo, sem a variável.") unless button["url_example"].to_s.match?(URL)
    end
  end
end
