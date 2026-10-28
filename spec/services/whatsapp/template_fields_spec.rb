require "rails_helper"

RSpec.describe Whatsapp::TemplateFields do
  def fields(text)
    described_class.new(build(:whatsapp_template, components: [ { "type" => "BODY", "text" => text } ]))
  end

  describe ".person" do
    it "tira o primeiro nome, o nome completo e a empresa do lead, do contato ou do perfil da conversa" do
      lead = build(:lead, name: "  Henrique   Duarte ", company_name: "Grupo Norte")
      contact = build(:contact, name: "Juliana Ferraz", company: build(:company, trade_name: "Empresa ACME"))

      expect(described_class.person(lead)).to eq(first_name: "Henrique", full_name: "Henrique Duarte", company: "Grupo Norte")
      expect(described_class.person(contact)).to eq(first_name: "Juliana", full_name: "Juliana Ferraz", company: "Empresa ACME")
      expect(described_class.person(build(:whatsapp_conversation, contact: contact))).to include(first_name: "Juliana")
      expect(described_class.person(build(:whatsapp_conversation, saved_name: "Lu Martins", profile_name: "Lu"))).to eq(first_name: "Lu", full_name: "Lu Martins")
      expect(described_class.person(build(:whatsapp_conversation, saved_name: nil, profile_name: nil))).to eq({})
    end
  end

  describe "#defaults" do
    let(:person) { { first_name: "Henrique", full_name: "Henrique Duarte", company: "Grupo Norte" } }

    it "preenche o {{1}} posicional e as variáveis nomeadas conhecidas; o resto fica em branco" do
      expect(fields("Olá, {{1}}. A proposta {{2}} vence em {{3}}.").defaults(person)[:body]).to eq([ "Henrique", nil, nil ])
      expect(fields("Olá, {{nome}} da {{empresa}}: {{nome_completo}}, {{prazo}}").defaults(person)[:body])
        .to eq([ "Henrique", "Grupo Norte", "Henrique Duarte", nil ])
    end

    it "os valores enviados valem mais que os sugeridos" do
      expect(fields("Olá, {{1}}.").defaults(person, values: { body: [ "Rique" ] })).to eq(body: [ "Rique" ], header: [], buttons: {})
    end
  end
end
