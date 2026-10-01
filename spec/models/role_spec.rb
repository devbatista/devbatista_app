require "rails_helper"

RSpec.describe Role do
  it { is_expected.to validate_presence_of(:name) }

  describe "#level_for" do
    it "dá acesso total ao administrador em qualquer área" do
      expect(build(:role, :admin).level_for("financeiro")).to eq("full")
    end

    it "usa a matriz inicial dos perfis" do
      comercial = build(:role, :comercial)
      expect(comercial.level_for("comercial")).to eq("edit")
      expect(comercial.level_for("financeiro")).to eq("none")
    end
  end

  it "só mostra cartões financeiros para Administrador e Financeiro" do
    expect(Role::DEFAULTS.keys.select { |key| build(:role, key.to_sym).sees_financials? }).to eq(%w[admin financeiro])
  end

  it "recusa área ou nível desconhecido" do
    role = build(:role, permissions: { "marte" => "full", "comercial" => "tudo" })
    expect(role).not_to be_valid
    expect(role.errors[:permissions].join).to include("marte").and include("tudo")
  end

  it "cria os cinco perfis sem duplicar" do
    2.times { described_class.seed_defaults! }
    expect(described_class.pluck(:key)).to match_array(Role::DEFAULTS.keys)
  end
end
