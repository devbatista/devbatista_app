require "rails_helper"

RSpec.describe Whatsapp::TemplateBuilder do
  def build(**attributes)
    described_class.new(name: "lembrete_proposta", language: "pt_BR", category: "utility",
                        body: "Olá, {{1}}. A proposta {{2}} vence em {{3}}. Ficou alguma dúvida?",
                        body_examples: [ "Beatriz", "Novo site", "20/09/2026" ], **attributes)
  end

  def errors_of(builder)
    builder.validate
    builder.errors.full_messages
  end

  it "monta o corpo com as variáveis e os exemplos, e o rodapé" do
    builder = build(footer: "DevBatista · responda SAIR para não receber")

    expect(builder).to be_valid
    expect(builder.components).to eq([
      { "type" => "BODY", "text" => "Olá, {{1}}. A proposta {{2}} vence em {{3}}. Ficou alguma dúvida?",
        "example" => { "body_text" => [ [ "Beatriz", "Novo site", "20/09/2026" ] ] } },
      { "type" => "FOOTER", "text" => "DevBatista · responda SAIR para não receber" }
    ])
    expect(builder.template_attributes).to include(name: "lembrete_proposta", language: "pt_BR", category: "utility")
  end

  it "não manda example quando o corpo não tem variável" do
    builder = build(body: "Obrigado pelo contato!", body_examples: [])
    expect(builder).to be_valid
    expect(builder.components).to eq([ { "type" => "BODY", "text" => "Obrigado pelo contato!" } ])
  end

  it "monta o cabeçalho de texto com o exemplo da variável e o de mídia com o handle" do
    text = build(header_type: "text", header_text: "Proposta {{1}}", header_example: "P-2026-029")
    expect(text).to be_valid
    expect(text.components.first).to eq("type" => "HEADER", "format" => "TEXT", "text" => "Proposta {{1}}", "example" => { "header_text" => [ "P-2026-029" ] })
    expect(build(header_type: "text", header_text: "Sua proposta").components.first).to eq("type" => "HEADER", "format" => "TEXT", "text" => "Sua proposta")

    media = build(header_type: "document", header_handle: "4::aW1hZ2UvanBlZw==:ARZ")
    expect(media).to be_valid
    expect(media.components.first).to eq("type" => "HEADER", "format" => "DOCUMENT", "example" => { "header_handle" => [ "4::aW1hZ2UvanBlZw==:ARZ" ] })
    expect(errors_of(build(header_type: "image"))).to include("Envie um arquivo de exemplo para o cabeçalho de imagem.")
  end

  it "monta os botões agrupados, com as respostas rápidas primeiro" do
    builder = build(buttons: [
      { type: "url", text: "Ver proposta", url: "https://admin.devbatista.com/p/{{1}}", url_example: "https://admin.devbatista.com/p/P-2026-029" },
      { type: "quick_reply", text: "Quero conversar" },
      { type: "url", text: "Site", url: "https://devbatista.com" },
      { type: "phone", text: "Ligar", phone: "+55 (11) 97070-2026" },
      { type: "quick_reply", text: "", url: "", phone: "" } # linha vazia some
    ])

    expect(builder).to be_valid
    expect(builder.components.last).to eq("type" => "BUTTONS", "buttons" => [
      { "type" => "QUICK_REPLY", "text" => "Quero conversar" },
      { "type" => "URL", "text" => "Ver proposta", "url" => "https://admin.devbatista.com/p/{{1}}", "example" => [ "https://admin.devbatista.com/p/P-2026-029" ] },
      { "type" => "URL", "text" => "Site", "url" => "https://devbatista.com" },
      { "type" => "PHONE_NUMBER", "text" => "Ligar", "phone_number" => "+5511970702026" }
    ])
  end

  it "recusa variável no início ou no fim, buraco na sequência, variáveis seguidas e exemplo faltando" do
    expect(errors_of(build(body: "{{1}}, sua proposta vence amanhã.", body_examples: [ "Beatriz" ])))
      .to include("O corpo não pode começar nem terminar com uma variável.")
    expect(errors_of(build(body: "Sua proposta vence em {{1}}", body_examples: [ "20/09" ])))
      .to include("O corpo não pode começar nem terminar com uma variável.")
    expect(errors_of(build(body: "Olá, {{1}}. A proposta {{3}} vence logo.", body_examples: %w[a b c])))
      .to include("As variáveis do corpo precisam estar em sequência, sem pular números ({{1}}, {{2}}…).")
    expect(errors_of(build(body: "Olá, {{1}} {{2}}, tudo bem?", body_examples: %w[a b])))
      .to include("O corpo tem variáveis seguidas, sem texto entre elas.")
    expect(errors_of(build(body_examples: [ "Beatriz", "" ]))).to include("Informe o exemplo de {{2}} e {{3}}.")
    expect(errors_of(build(body: "Olá, {{nome}}. Tudo bem?"))).to include("Use variáveis numeradas: {{1}}, {{2}}…")
  end

  it "recusa os limites de caracteres e de botões" do
    expect(errors_of(build(body: "a#{'x' * 1024}", body_examples: []))).to include("O corpo tem até 1024 caracteres.")
    expect(errors_of(build(header_type: "text", header_text: "x" * 61))).to include("O cabeçalho tem até 60 caracteres.")
    expect(errors_of(build(header_type: "text", header_text: "{{1}} e {{2}}", header_example: "a"))).to include("O cabeçalho aceita só uma variável, {{1}}.")
    expect(errors_of(build(footer: "x" * 61))).to include("O rodapé tem até 60 caracteres.")
    expect(errors_of(build(footer: "Até {{1}}"))).to include("O rodapé não aceita variáveis.")

    quick = Array.new(11) { |i| { type: "quick_reply", text: "Opção #{i}" } }
    expect(errors_of(build(buttons: quick))).to include("São até 10 botões.")
    links = Array.new(3) { { type: "url", text: "Site", url: "https://devbatista.com" } }
    expect(errors_of(build(buttons: links))).to include("São até 2 botões de link.")
    phones = Array.new(2) { { type: "phone", text: "Ligar", phone: "+5511970702026" } }
    expect(errors_of(build(buttons: phones))).to include("É só 1 botão de telefone.")
    expect(errors_of(build(buttons: [ { type: "quick_reply", text: "x" * 26 } ]))).to include("Botão 1: o texto tem até 25 caracteres.")
    expect(errors_of(build(buttons: [ { type: "url", text: "Ver", url: "https://a.com/{{1}}/x", url_example: "https://a.com/1/x" } ])))
      .to include("Botão 1: o link aceita só uma variável, {{1}}, no fim.")
    expect(errors_of(build(buttons: [ { type: "url", text: "Ver", url: "https://a.com/p/{{1}}" } ])))
      .to include("Botão 1: informe um exemplo do link completo, sem a variável.")
    expect(errors_of(build(buttons: [ { type: "phone", text: "Ligar", phone: "123" } ]))).to include("Botão 1: informe o telefone com DDI, como +5511999998888.")
  end

  it "recusa nome fora do padrão e categoria de autenticação" do
    expect(errors_of(build(name: "Lembrete Proposta"))).to include("O nome usa só letras minúsculas, números e _ (sublinhado).")
    expect(errors_of(build(category: "authentication"))).to include("Escolha a categoria: Marketing ou Utilidade.")
    expect(errors_of(build(language: "fr"))).to include("Escolha o idioma: português, inglês ou espanhol.")
  end

  it "remonta os campos a partir de um template gravado, para editar" do
    original = build(header_type: "text", header_text: "Proposta {{1}}", header_example: "P-1", footer: "DevBatista",
                     buttons: [ { type: "url", text: "Ver", url: "https://admin.devbatista.com/p/{{1}}", url_example: "https://admin.devbatista.com/p/P-1" },
                                { type: "phone", text: "Ligar", phone: "+5511970702026" } ])
    template = build_stubbed(:whatsapp_template, original.template_attributes)

    copy = described_class.from_template(template)
    expect(copy.components).to eq(original.components)
    expect(copy).to have_attributes(name: "lembrete_proposta", header_type: "text", body_examples: [ "Beatriz", "Novo site", "20/09/2026" ])
  end
end
