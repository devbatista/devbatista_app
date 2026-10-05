require "rails_helper"

RSpec.describe "Financeiro" do
  let(:financeiro) { create(:user, :financeiro) }
  let(:company) { create(:company, trade_name: "Empresa ACME") }

  describe "Dashboard financeiro" do
    it "mostra os 7 cartões e a composição do faturamento" do
      create(:receivable, company: company, amount_cents: 300_000, paid_on: Date.current, due_on: Date.current)
      create(:receivable, company: company, amount_cents: 120_000, due_on: Date.current - 2)
      create(:payable, amount_cents: 50_000)
      sign_in financeiro
      get finance_path
      expect(response.body).to include("Faturamento", "Recebido", "A receber", "Vencido", "Despesas", "Resultado", "MRR",
                                        "R$ 4.200", "R$ 3.700", "Inadimplentes")
    end

    it "responde 403 para quem não acessa o Financeiro" do
      sign_in create(:user, :comercial)
      get finance_path
      expect(response).to have_http_status(:forbidden)
      get receivables_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Receitas e contas a receber" do
    it "lista por competência e por vencimento, com inadimplentes de qualquer mês" do
      create(:receivable, company: company, description: "Manutenção — Setembro/2026", due_on: Date.current - 40, competence: Date.current << 1)
      create(:receivable, company: company, description: "Hospedagem — Outubro/2026")
      sign_in financeiro
      get revenues_path
      expect(response.body).to include("Hospedagem — Outubro/2026", "Faturamento da competência")
      get receivables_path(status: "overdue")
      expect(response.body).to include("Manutenção — Setembro/2026", "Inadimplentes", "40 dias")
    end

    it "cadastra uma receita avulsa e registra o pagamento" do
      service = create(:service, name: "Publicação de aplicativos", kind: "one_off")
      sign_in financeiro
      post receivables_path, params: { receivable: { company_id: company.id, description: "Publicação do app", service_id: service.id,
                                                     amount: "200,00", competence_month: Date.current.strftime("%Y-%m"), due_on: Date.current + 5 } }
      receivable = Receivable.last
      expect(receivable).to have_attributes(category: "Publicação de aplicativos", amount_cents: 20_000, status: "pending")
      patch payment_receivable_path(receivable), params: { payment: { paid_on: Date.current, amount: "200,00" } }
      expect(receivable.reload).to be_paid
    end
  end

  describe "Despesas e contas a pagar" do
    let(:supplier) { create(:supplier, name: "Railway", category: "Infraestrutura") }

    it "cadastra despesa recorrente em dólar, que cria a regra" do
      ExchangeRate.create!(currency: "USD", quoted_on: Date.current, rate: 5.62)
      sign_in financeiro
      post payables_path, params: { recorrente: "1", periodicidade: "monthly",
                                    payable: { supplier_id: supplier.id, description: "Hospedagem — Sistema ERP", currency: "USD", original_amount: "20,00",
                                               competence_month: Date.current.strftime("%Y-%m"), due_on: Date.current + 3, cost_center_key: "company:#{company.id}" } }
      payable = Payable.last
      expect(payable).to have_attributes(amount_cents: 11_240, category: "Infraestrutura", company: company)
      expect(payable.recurring_expense).to have_attributes(currency: "USD", amount_cents: 2_000, due_day: payable.due_on.day, periodicity: "monthly")
      get expenses_path
      expect(response.body).to include("Railway", "≈ R$ 112,40", "US$ 20,00")
    end

    it "registra o pagamento em dólar com a PTAX da data" do
      ExchangeRate.create!(currency: "USD", quoted_on: Date.current, rate: 5.62)
      payable = create(:payable, supplier: supplier, currency: "USD", original_amount: 20, amount_cents: nil)
      sign_in financeiro
      patch payment_payable_path(payable), params: { payment: { paid_on: Date.current, original_amount: "20,00", rate: "", amount: "" } }
      expect(payable.reload).to have_attributes(status: "paid", amount_cents: 11_240)
    end

    it "volta com erro sem centro de custo" do
      sign_in financeiro
      post payables_path, params: { payable: { supplier_id: supplier.id, description: "X", currency: "BRL", amount: "10",
                                               competence_month: Date.current.strftime("%Y-%m"), due_on: Date.current } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Centro de custo precisa ser uma área interna ou um cliente")
    end
  end

  describe "Recorrências e notas fiscais" do
    it "executa a rotina pelo botão e mostra as regras" do
      create(:customer_service, company: company, price_cents: 300_000, start_date: Date.current - 60, due_day: 28)
      sign_in financeiro
      post run_recurrences_path
      expect(response).to redirect_to(recurrences_path)
      expect(Receivable.count).to eq(4)
      follow_redirect!
      expect(response.body).to include("Rotina executada", "Empresa ACME", "Receitas recorrentes")
    end

    it "registra a nota fiscal com PDF ligada à receita" do
      receivable = create(:receivable, company: company)
      sign_in financeiro
      get invoices_path
      expect(response.body).to include("Receitas sem nota", receivable.description)
      post invoices_path, params: { invoice: { company_id: company.id, number: "000418", competence_month: Date.current.strftime("%Y-%m"),
                                               amount: "3000", issued_on: Date.current, status: "issued", receivable_ids: [ receivable.id ],
                                               files: [ Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", original_filename: "nota.pdf") ] } }
      invoice = Invoice.last
      expect(invoice.files.count).to eq(1)
      expect(receivable.reload.invoice).to eq(invoice)
      get file_invoice_path(invoice, file_id: invoice.files.first.id)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "Fornecedores" do
    it "deixa o desenvolvedor consultar, mas não cadastrar" do
      create(:supplier, name: "Cloudflare")
      sign_in create(:user, :desenvolvedor)
      get suppliers_path
      expect(response.body).to include("Cloudflare")
      post suppliers_path, params: { supplier: { name: "X", category: "Software" } }
      expect(response).to have_http_status(:forbidden)
    end

    it "cadastra pelo financeiro" do
      sign_in financeiro
      post suppliers_path, params: { supplier: { name: "DigitalOcean", category: "Infraestrutura", website: "digitalocean.com" } }
      expect(Supplier.find_by!(name: "DigitalOcean").website_url).to eq("https://digitalocean.com")
    end
  end

  describe "Visão 360º e busca" do
    it "mostra a aba Financeiro e a próxima cobrança pelos títulos" do
      create(:receivable, company: company, description: "Consultoria de TI — Outubro/2026", amount_cents: 380_000, due_on: Date.current + 5)
      sign_in financeiro
      get company_path(company)
      expect(response.body).to include('data-tab="financeiro"', "Títulos a receber", "Consultoria de TI — Outubro/2026", "1 título")
    end

    it "esconde a aba Financeiro de quem não tem acesso" do
      sign_in create(:user, :suporte)
      get company_path(company)
      expect(response.body).not_to include('data-tab="financeiro"')
    end

    it "encontra faturas e notas fiscais" do
      create(:receivable, company: company, description: "Hospedagem — Outubro/2026")
      create(:invoice, company: company, number: "000418")
      sign_in financeiro
      get search_path(q: "ACME", format: :json)
      expect(response.parsed_body.map { |g| g["label"] }).to include("Faturas")
      get search_path(q: "000418", format: :json)
      expect(response.parsed_body.map { |g| g["label"] }).to include("Notas fiscais")
    end
  end
end
