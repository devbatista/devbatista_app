require "rails_helper"

RSpec.describe "Gestão e dashboard" do
  let(:admin) { create(:user, :admin) }
  let(:financeiro) { create(:user, :financeiro) }
  let(:company) { create(:company, trade_name: "Empresa ACME", customer_since: Date.current << 6) }

  before do
    create(:customer_service, company: company, price_cents: 380_000, start_date: Date.current << 6)
    create(:receivable, company: company, amount_cents: 400_000)
    create(:payable, amount_cents: 150_000, category: "Marketing")
  end

  describe "Dashboard executivo" do
    it "mostra os 12 cartões, os 6 gráficos e o feed para quem vê o financeiro" do
      sign_in financeiro
      get root_path
      expect(response.body).to include("Faturamento", "Receita recebida", "Receita prevista", "Despesas", "Resultado", "MRR",
                                        "Clientes ativos", "Contratos ativos", "Projetos ativos", "Chamados abertos", "Contas vencidas",
                                        "Propostas abertas", "R$ 4.000", "R$ 3.800", "Evolução do MRR", "Receita por serviço",
                                        "Receita por cliente", "Atividades recentes")
      expect(response.body).to include(revenues_path(periodo: Date.current.strftime("%Y-%m")))
    end

    it "esconde cartões e gráficos financeiros de quem não vê o financeiro" do
      sign_in create(:user, :suporte)
      get root_path
      expect(response.body).to include("Clientes ativos", "Chamados abertos")
      expect(response.body).not_to include("Receita recebida", "Contas vencidas", "Evolução do MRR", "R$ 4.000")
    end

    it "aceita o trimestre como período" do
      sign_in admin
      get root_path(periodo: "trimestre")
      expect(response.body).to include("Trimestre atual")
    end
  end

  describe "Indicadores" do
    it "calcula os 14 indicadores com definição e comparação" do
      sign_in admin
      get indicators_path
      expect(response.body).to include("MRR", "ARR", "Faturamento", "Margem", "Ticket médio", "Custo de infraestrutura", "Clientes ativos",
                                        "CAC", "Churn", "Propostas abertas", "Horas por cliente", "Receita por cliente", "Receita por serviço",
                                        "Taxa de conversão por origem", "R$ 45.600", "Calculados pelo sistema")
    end

    it "mostra ao Suporte só os indicadores das áreas dele" do
      sign_in create(:user, :suporte)
      get indicators_path
      expect(response.body).to include("Clientes ativos", "Churn")
      expect(response.body).not_to include("ARR", "Ticket médio", "CAC", "R$ 45.600")
    end
  end

  describe "Rentabilidade por cliente" do
    it "lista o ranking, detalha os custos do cliente e exporta CSV" do
      create(:server, company: company, name: "acme-worker-01", monthly_cost_cents: 22_000)
      sign_in financeiro
      get profitability_path(cliente: company.id)
      expect(response.body).to include("Ranking de margem por cliente", "Empresa ACME", "acme-worker-01", "R$ 3.780", "94,5%", "Depois do MVP")
      get profitability_path(format: :csv)
      expect(response.media_type).to eq "text/csv"
      expect(response.body).to include("Empresa ACME;4000,00;220,00;3780,00;94,50;acme-worker-01")
    end

    it "responde 403 para quem não vê o financeiro" do
      sign_in create(:user, :comercial)
      get profitability_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Relatórios" do
    it "lista os 19 para o administrador e abre um com tabela, filtros e gráfico" do
      sign_in admin
      get reports_path
      expect(response.body.scan('class="card rep').size).to eq 19
      get report_path("receita-por-cliente", cliente: company.id)
      expect(response.body).to include("Receita por cliente", "Empresa ACME", "R$ 4.000", "Participação no faturamento", "Todos os serviços")
    end

    it "exporta o CSV do relatório" do
      sign_in financeiro
      get report_path("faturamento", format: :csv)
      expect(response.body).to start_with("﻿Mês;Faturado;Recebido;A receber;Vencido\r\n")
      expect(response.body).to include("4000,00")
    end

    it "aceita período personalizado" do
      sign_in admin
      get report_path("despesas", periodo: "personalizado", de: Date.current.beginning_of_month.iso8601, ate: Date.current.iso8601)
      expect(response.body).to include("Marketing", "R$ 1.500", I18n.l(Date.current.beginning_of_month))
    end

    it "respeita o perfil: Suporte não vê os financeiros nem os comerciais" do
      sign_in create(:user, :suporte)
      get reports_path
      expect(response.body).to include("Chamados", "Clientes ativos")
      expect(response.body).not_to include("Faturamento", "Leads")
      get report_path("faturamento")
      expect(response).to have_http_status(:forbidden)
      get report_path("chamados", format: :csv)
      expect(response).to have_http_status(:ok)
    end

    it "calcula cada um dos 19 sem erro" do
      sign_in admin
      ReportCatalog::REPORTS.each do |report|
        get report_path(report.key, periodo: "ano")
        expect(response).to have_http_status(:ok), report.key
      end
    end
  end
end
