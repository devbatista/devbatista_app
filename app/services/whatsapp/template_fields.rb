module Whatsapp
  # O que o envio de um template aprovado pede (docs/specs/whatsapp, Fase 6): as variáveis do corpo
  # e do cabeçalho de texto, a mídia do cabeçalho e o sufixo dos botões de URL com variável. Serve
  # ao servidor (Whatsapp::Outbound) e ao campo de envio (to_h, em JSON para o Stimulus).
  #
  # Corpo posicional ({{1}}, {{2}}…) vai como lista; nomeado ({{nome}}), como parâmetros nomeados.
  #
  # Valores sugeridos (Fase 7b): o {{1}} do corpo e as variáveis nomeadas conhecidas (PREFILL) já vêm
  # preenchidos com os dados do lead, do contato ou do perfil da conversa (person). O resto fica em
  # branco para a pessoa preencher; tudo pode ser editado antes do envio.
  class TemplateFields
    VARIABLE = WhatsappTemplate::VARIABLE
    PREFILL = {
      "nome" => :first_name, "primeiro_nome" => :first_name, "first_name" => :first_name, "name" => :first_name,
      "nome_completo" => :full_name, "full_name" => :full_name,
      "empresa" => :company, "company" => :company, "company_name" => :company
    }.freeze

    # Primeiro nome, nome completo e empresa de quem vai receber: o lead ou o contato, ou, numa
    # conversa sem vínculo, o nome da agenda ou do perfil (sem empresa).
    def self.person(record)
      case record
      when Lead then person_data(record.name, record.company_name)
      when Contact then person_data(record.name, record.company&.trade_name)
      when WhatsappConversation then record.link ? person(record.link) : person_data(record.saved_name || record.profile_name, nil)
      else {}
      end
    end

    def self.person_data(name, company)
      name = name.to_s.squish
      { first_name: name.split.first, full_name: name.presence, company: company.to_s.squish.presence }.compact
    end

    attr_reader :template

    def initialize(template)
      @template = template
    end

    # Nomes das variáveis do corpo, na ordem de envio: 1, 2, 3… ou os nomes, na ordem em que aparecem.
    def body_names
      @body_names ||= begin
        names = template.body_text.scan(VARIABLE).flatten.map(&:strip).uniq
        names.all? { |name| name.match?(/\A\d+\z/) } ? names.map(&:to_i).sort.map(&:to_s) : names
      end
    end

    def named?
      body_names.any? { |name| !name.match?(/\A\d+\z/) }
    end

    def body_count
      body_names.size
    end

    def header
      template.component("HEADER") || {}
    end

    def header_count
      header["format"].to_s.casecmp?("TEXT") && header["text"].to_s.match?(VARIABLE) ? 1 : 0
    end

    # image, document ou video quando o cabeçalho é de mídia.
    def header_media
      format = header["format"].to_s.downcase
      format if TemplateBuilder::MEDIA_HEADERS.include?(format)
    end

    def buttons
      Array(template.component("BUTTONS")&.dig("buttons"))
    end

    # Posição (0, 1…) dos botões de URL com variável, como a Cloud API pede no envio.
    def url_button_indexes
      buttons.each_index.select { |index| buttons[index]["type"] == "URL" && buttons[index]["url"].to_s.match?(VARIABLE) }
    end

    # Corpo com os valores no lugar das variáveis, para a linha do tempo e a prévia da lista.
    def fill(values)
      lookup = body_names.zip(values).to_h
      template.body_text.gsub(VARIABLE) { lookup[Regexp.last_match(1).strip].presence || Regexp.last_match(0) }
    end

    # Parâmetros do corpo no formato do TemplateComponents.build.
    def body_parameters(values)
      named? ? body_names.zip(values).to_h : values
    end

    # Valores do corpo, do cabeçalho de texto e dos botões para os campos. values: os enviados (o
    # formulário que voltou com erro), que valem mais que os sugeridos.
    def defaults(person = {}, values: nil)
      return { body: Array(values[:body]), header: Array(values[:header]), buttons: values[:buttons].to_h } if values

      { body: body_names.map { |name| person[name == "1" ? :first_name : PREFILL[name.downcase]] }, header: [], buttons: {} }
    end

    def to_h(person: {}, values: nil)
      { id: template.id, defaults: defaults(person, values: values), name: template.name, language: template.language, label: "#{template.name} · #{template.category_label} · #{template.language_label}",
        body: template.body_text, body_names: body_names, header_text: (header["text"] if header_count.positive?),
        header_media: header_media, footer: template.component("FOOTER")&.dig("text"),
        buttons: buttons.map { |button| { type: button["type"], text: button["text"] } }, url_buttons: url_button_indexes }
    end
  end
end
