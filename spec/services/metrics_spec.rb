require "rails_helper"

RSpec.describe Metrics do
  let(:month) { Date.current.all_month }
  let(:metrics) { described_class.new(month) }

  describe "#churn" do
    it "conta quem saiu no período sobre a base do início e trata a volta como reativação" do
      staying = create(:company, customer_since: Date.current << 6)
      create(:customer_service, company: staying, start_date: Date.current << 6)
      leaving = create(:company, customer_since: Date.current << 6)
      create(:customer_service, company: leaving, start_date: Date.current << 6, price_cents: 45_000, status: "ended", ended_on: Date.current.beginning_of_month + 1)
      returning = create(:company, customer_since: Date.current << 12)
      create(:customer_service, company: returning, start_date: Date.current << 12, status: "ended", ended_on: Date.current << 4)
      create(:customer_service, company: returning, start_date: Date.current.beginning_of_month)

      churn = metrics.churn
      expect(churn).to include(base: 2, lost: 1, lost_mrr: 45_000, rate: 50.0, lost_ids: [ leaving.id ], reactivated_ids: [ returning.id ])
      expect(metrics.new_clients).to be_empty
    end

    it "não divide por zero sem base" do
      expect(metrics.churn).to include(base: 0, rate: nil, mrr_rate: nil)
    end
  end

  describe "#cac_cents" do
    it "divide Marketing e Comercial da competência pelos novos clientes" do
      create(:company, customer_since: Date.current.beginning_of_month)
      create(:payable, category: "Marketing", amount_cents: 100_000)
      create(:payable, category: "Comercial", amount_cents: 50_000)
      create(:payable, category: "Infraestrutura", amount_cents: 99_000)
      expect(metrics.cac_cents).to eq 150_000
    end

    it "fica vazio sem novos clientes" do
      create(:payable, category: "Marketing")
      expect(metrics.cac_cents).to be_nil
    end
  end

  describe ".mrr_by_company" do
    it "mostra o MRR de uma data passada, sem os serviços que ainda não tinham começado" do
      company = create(:company)
      create(:customer_service, company: company, start_date: Date.current << 3, price_cents: 120_000, recurrence: "quarterly")
      create(:customer_service, company: company, start_date: Date.current.beginning_of_month)
      expect(described_class.mrr_by_company((Date.current << 1).end_of_month)).to eq(company.id => 40_000)
      expect(described_class.mrr_by_company(Date.current)[company.id]).to eq 140_000
    end
  end

  describe "#profitability" do
    it "subtrai os custos diretos da receita sem contar duas vezes o serviço externo" do
      company = create(:company, trade_name: "Empresa ACME")
      create(:receivable, company: company, amount_cents: 400_000)
      create(:server, company: company, monthly_cost_cents: 22_000)
      service = create(:external_service, company: company, currency: "BRL", cost_cents: 8_000)
      create(:payable, company: company, cost_center: nil, external_service: service, amount_cents: 8_000)
      create(:payable, company: company, cost_center: nil, amount_cents: 22_000, description: "EC2 + RDS")
      create(:external_service, company: company, currency: "BRL", cost_cents: 5_000, paid_by: "client")

      row = metrics.profitability.find { |r| r[:company] == company }
      expect(row).to include(revenue: 400_000, cost: 52_000, margin: 348_000, margin_percent: 87.0)
      expect(row[:lines].map { |l| l[:cents] }).to eq [ 22_000, 22_000, 8_000 ]
    end
  end
end
