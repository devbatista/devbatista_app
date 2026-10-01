require "rails_helper"

RSpec.describe Company do
  it "valida o CNPJ pelos dígitos verificadores" do
    company = build(:company, cnpj: "11.222.333/0001-82")
    expect(company).not_to be_valid
    expect(company.errors[:cnpj]).to include("não é um CNPJ válido")
  end

  it "não aceita CNPJ repetido, mesmo com máscara diferente" do
    create(:company, cnpj: "11222333000181")
    expect(build(:company, cnpj: "11.222.333/0001-81")).not_to be_valid
  end

  it "guarda só os dígitos e mostra com máscara" do
    company = create(:company, cnpj: "11.222.333/0001-81")
    expect(company.cnpj).to eq("11222333000181")
    expect(company.formatted_cnpj).to eq("11.222.333/0001-81")
  end

  it "registra 'cliente desde' quando vira Ativo" do
    company = create(:company, status: "prospect")
    expect(company.customer_since).to be_nil
    company.update!(status: "active")
    expect(company.customer_since).to eq(Date.current)
  end

  it "soma o MRR só dos serviços ativos" do
    company = create(:company)
    create(:customer_service, company: company, price_cents: 300_000)
    create(:customer_service, company: company, price_cents: 90_000, recurrence: "quarterly")
    create(:customer_service, company: company, price_cents: 50_000, status: "suspended")
    create(:customer_service, company: company, price_cents: 20_000, recurrence: "one_off")
    expect(company.mrr_cents).to eq(330_000)
  end

  it "calcula a próxima cobrança pelos serviços ativos" do
    company = create(:company)
    create(:customer_service, company: company, price_cents: 300_000, start_date: Date.new(2026, 3, 12), due_day: 10)
    create(:customer_service, company: company, price_cents: 50_000, start_date: Date.new(2026, 7, 1), due_day: 10)
    expect(company.next_charge(Date.new(2026, 9, 17))).to eq(date: Date.new(2026, 10, 10), cents: 350_000)
  end

  it "monta as iniciais como no design" do
    expect(build(:company, trade_name: "Empresa ACME").initials).to eq("AC")
    expect(build(:company, trade_name: "Cliente A").initials).to eq("CA")
  end

  it "busca sem diferenciar acentos" do
    create(:company, trade_name: "Logística São João")
    expect(described_class.search("logistica sao joao").count).to eq(1)
  end

  it "registra criação e mudança de status no histórico" do
    company = create(:company, status: "prospect")
    company.update!(status: "active")
    expect(company.activities.recent.first.description).to eq("Mudou o status de a empresa #{company.trade_name}: Prospect → Ativo")
    expect(AuditLog.where(auditable: company).pluck(:action)).to eq(%w[create status_change])
  end
end
