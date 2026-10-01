require "rails_helper"

RSpec.describe CustomerService do
  it "calcula o MRR pela recorrência (mensal, ÷3, ÷6, ÷12; avulso fora)" do
    expect(create(:customer_service, price_cents: 300_000, recurrence: "monthly").mrr_cents).to eq(300_000)
    expect(create(:customer_service, price_cents: 360_000, recurrence: "quarterly").mrr_cents).to eq(120_000)
    expect(create(:customer_service, price_cents: 1_800_000, recurrence: "semiannual").mrr_cents).to eq(300_000)
    expect(create(:customer_service, price_cents: 960_000, recurrence: "annual").mrr_cents).to eq(80_000)
    expect(create(:customer_service, price_cents: 20_000, recurrence: "one_off").mrr_cents).to eq(0)
  end

  it "zera o MRR quando o serviço é suspenso e recalcula ao reativar" do
    service = create(:customer_service, price_cents: 300_000)
    service.update!(status: "suspended")
    expect(service.mrr_cents).to eq(0)
    service.update!(status: "active")
    expect(service.mrr_cents).to eq(300_000)
  end

  it "registra a data de encerramento" do
    service = create(:customer_service)
    service.update!(status: "ended")
    expect(service.ended_on).to eq(Date.current)
  end

  it "não aceita contrato de outra empresa" do
    service = build(:customer_service, contract: create(:contract))
    expect(service).not_to be_valid
    expect(service.errors[:contract]).to include("é de outra empresa")
  end

  it "calcula o próximo vencimento pela recorrência" do
    service = build(:customer_service, recurrence: "quarterly", start_date: Date.new(2026, 1, 15), due_day: 10)
    expect(service.next_due_date(Date.new(2026, 5, 1))).to eq(Date.new(2026, 7, 10))
  end
end
