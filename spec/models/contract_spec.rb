require "rails_helper"

RSpec.describe Contract do
  it "gera o número sequencial no banco" do
    first = create(:contract)
    second = create(:contract)
    expect(second.number).to eq(first.number + 1)
    expect(first.code).to match(/\A#\d{3,}\z/)
  end

  it "exige término depois do início" do
    contract = build(:contract, start_date: Date.current, end_date: Date.current)
    expect(contract).not_to be_valid
  end

  it "mensaliza o valor pela periodicidade" do
    expect(build(:contract, value_cents: 960_000, periodicity: "annual").monthly_value_cents).to eq(80_000)
    expect(build(:contract, value_cents: 500_000, periodicity: "one_time").monthly_value_cents).to eq(0)
  end

  it "descreve a renovação em texto corrido" do
    expect(build(:contract, renewal: "none").renewal_text).to eq("sem renovação")
    expect(build(:contract, renewal: "automatic").renewal_text).to eq("renovação automática")
  end
end
