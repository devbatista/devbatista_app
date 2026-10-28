require "rails_helper"

RSpec.describe Whatsapp::Phone do
  describe ".stored_forms" do
    it "dá o celular do Brasil com e sem o nono dígito, com e sem o 55 e o 0 do DDD" do
      expect(described_class.stored_forms("5511991023344")).to contain_exactly(
        "11991023344", "5511991023344", "011991023344", "1191023344", "551191023344", "01191023344"
      )
      expect(described_class.stored_forms("551191023344")).to include("11991023344", "1191023344")
    end

    it "deixa o fixo e o número de fora do Brasil como estão" do
      expect(described_class.stored_forms("551131234567")).to contain_exactly("1131234567", "551131234567", "01131234567")
      expect(described_class.stored_forms("14155550100")).to eq([ "14155550100" ])
      expect(described_class.stored_forms(nil)).to eq([])
    end
  end

  describe ".wa_ids" do
    it "lê o telefone como foi digitado no cadastro" do
      expect(described_class.wa_ids("(11) 99102-3344")).to contain_exactly("5511991023344", "551191023344")
      expect(described_class.wa_ids("011 9102-3344")).to contain_exactly("551191023344", "5511991023344")
      expect(described_class.wa_ids("+55 11 99102-3344")).to contain_exactly("5511991023344", "551191023344")
      expect(described_class.wa_ids("(55) 3221-4455")).to eq([ "555532214455" ]) # DDD 55, fixo
      expect(described_class.wa_ids("+1 415 555 0100")).to eq([ "14155550100" ])
      expect(described_class.wa_ids("ramal 12")).to eq([])
    end
  end

  it ".national_label formata para o cadastro" do
    expect(described_class.national_label("5511991023344")).to eq("(11) 99102-3344")
    expect(described_class.national_label("551131234567")).to eq("(11) 3123-4567")
    expect(described_class.national_label("14155550100")).to eq("+14155550100")
    expect(described_class.national_label(nil)).to be_nil
  end
end
