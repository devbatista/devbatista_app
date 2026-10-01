require "rails_helper"

RSpec.describe CnpjValidator do
  it "aceita CNPJ com dígitos verificadores corretos, com ou sem máscara" do
    expect(described_class.valid?("11.222.333/0001-81")).to be(true)
    expect(described_class.valid?("11222333000181")).to be(true)
  end

  it "recusa dígito errado, tamanho errado e números repetidos" do
    expect(described_class.valid?("11.222.333/0001-82")).to be(false)
    expect(described_class.valid?("1122233300018")).to be(false)
    expect(described_class.valid?("11.111.111/1111-11")).to be(false)
  end

  it "formata com a máscara" do
    expect(described_class.format("11222333000181")).to eq("11.222.333/0001-81")
  end
end
