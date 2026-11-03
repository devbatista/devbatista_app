require "rails_helper"
require "aws-sdk-invoicing"
require "aws-sdk-costexplorer"

RSpec.describe "Faturas de fornecedores pela API" do
  let(:today) { Date.new(2026, 11, 10) }
  let(:connection) { create(:billing_connection) }

  before do
    travel_to today
    ExchangeRate.create!(currency: "USD", quoted_on: today - 30, rate: 5.5)
  end

  # Cliente de API de mentira: devolve as cobranças passadas, ou levanta o erro.
  def fake_client(*charges, error: nil)
    double("client").tap do |client|
      if error then allow(client).to receive(:charges).and_raise(error)
      else allow(client).to receive(:charges).and_return(charges)
      end
    end
  end

  def charge(**attributes)
    Billing::Charge.new(external_id: "invoice:1", description: "AWS — fatura 1 (Outubro/2026)", competence: Date.new(2026, 10),
                        due_on: today + 5, currency: "USD", amount_cents: 1_000, **attributes)
  end

  describe Billing::Sync do
    it "lança a estimativa como prevista e a substitui pela fatura fechada" do
      estimate = charge(external_id: "estimate:2026-11", competence: Date.new(2026, 11), due_on: Date.new(2026, 12, 3),
                        status: :forecast, amount_cents: 1_200)
      result = described_class.new(connection, client: fake_client(estimate)).run
      payable = connection.payables.sole
      expect(result.created).to eq(1)
      expect(payable).to have_attributes(status: "forecast", currency: "USD", original_amount_cents: 1_200, amount_cents: 6_600,
                                         category: "Infraestrutura", cost_center: "Infraestrutura interna", supplier: connection.supplier)
      expect(payable).to be_imported

      invoice = charge(external_id: "invoice:9", competence: Date.new(2026, 11), replaces: [ "estimate:2026-11" ])
      result = described_class.new(connection, client: fake_client(invoice)).run
      expect(result.cancelled).to eq(1)
      expect(payable.reload).to be_cancelled
      expect(connection.payables.find_by(external_id: "invoice:9")).to have_attributes(status: "pending", original_amount_cents: 1_000)
    end

    it "não duplica e atualiza o valor nas próximas rodadas" do
      described_class.new(connection, client: fake_client(charge)).run
      result = described_class.new(connection, client: fake_client(charge(amount_cents: 1_500))).run
      expect(connection.payables.count).to eq(1)
      expect(result.updated).to eq(1)
      expect(connection.payables.sole.original_amount_cents).to eq(1_500)
      expect(described_class.new(connection, client: fake_client(charge(amount_cents: 1_500))).run.to_s).to eq("nenhuma mudança")
    end

    it "com cobrança no cartão, dá a fatura como paga no vencimento pela PTAX do dia" do
      ExchangeRate.create!(currency: "USD", quoted_on: today - 2, rate: 5.0)
      described_class.new(connection, client: fake_client(charge(due_on: today - 2))).run
      expect(connection.payables.sole).to have_attributes(status: "paid", paid_on: today - 2, amount_cents: 5_000)
    end

    it "sem cobrança no cartão, deixa vencida a fatura que o fornecedor não diz que foi paga" do
      connection.update!(auto_paid: false)
      described_class.new(connection, client: fake_client(charge(due_on: today - 2))).run
      expect(connection.payables.sole).to be_overdue
    end

    it "usa o pagamento informado pelo fornecedor e lança em reais sem conversão" do
      paid = charge(currency: "BRL", amount_cents: 4_990, status: :paid, paid_on: today - 1, due_on: today - 1)
      described_class.new(connection, client: fake_client(paid)).run
      expect(connection.payables.sole).to have_attributes(status: "paid", amount_cents: 4_990, original_amount_cents: nil)
    end

    it "não mexe em despesa já paga ou cancelada" do
      described_class.new(connection, client: fake_client(charge)).run
      connection.payables.sole.cancel!("lançada em duplicidade")
      described_class.new(connection, client: fake_client(charge(amount_cents: 9_999))).run
      expect(connection.payables.sole).to have_attributes(status: "cancelled", original_amount_cents: 1_000)
    end

    it "guarda a falha, avisa o Financeiro uma vez e limpa o erro quando volta a funcionar" do
      create(:user, :financeiro)
      sync = -> { described_class.new(connection, client: fake_client(error: Billing::Error.new("token inválido"))).run }
      expect { 2.times { sync.call } }.to change(Notification.where(kind: "billing_sync_failed"), :count).by(1)
      expect(connection.reload.last_error).to eq("token inválido")
      expect(connection.payables).to be_empty

      described_class.new(connection, client: fake_client(charge)).run
      expect(connection.reload).to have_attributes(last_error: nil, last_synced_at: be_present)
    end

    it "recusa moeda que o Admin não converte e não lança nada da rodada" do
      described_class.new(connection, client: fake_client(charge(external_id: "a"), charge(external_id: "b", currency: "GBP"))).run
      expect(connection.reload.last_error).to include("GBP")
      expect(connection.payables).to be_empty
    end

    it "falha sem as variáveis de ambiente das chaves" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("BILLING_AWS_ACCESS_KEY_ID").and_return(nil)
      expect(described_class.new(connection).run).to be_nil
      expect(connection.reload.last_error).to include("BILLING_AWS_ACCESS_KEY_ID")
    end
  end

  describe Billing::Aws do
    let(:invoicing) { Aws::Invoicing::Client.new(stub_responses: true) }
    let(:cost_explorer) { Aws::CostExplorer::Client.new(stub_responses: true) }
    let(:client) { described_class.new(connection, invoicing: invoicing, cost_explorer: cost_explorer, env: {}) }

    def summary(id, month:, total:, currency: "USD", type: "INVOICE")
      { invoice_id: id, account_id: connection.account_id, invoice_type: type, issued_date: Time.utc(2026, month + 1, 2),
        due_date: Time.utc(2026, month + 1, 2), billing_period: { month: month, year: 2026 },
        base_currency_amount: { total_amount: total, currency_code: currency } }
    end

    it "lê as faturas dos últimos meses e a estimativa do mês corrente" do
      invoicing.stub_responses(:list_invoice_summaries,
        { invoice_summaries: [] },
        { invoice_summaries: [ summary("EUINBR26-1", month: 10, total: "12.34"), summary("CM-1", month: 10, total: "3.00", type: "CREDIT_MEMO") ] },
        { invoice_summaries: [] }, { invoice_summaries: [] })
      cost_explorer.stub_responses(:get_cost_and_usage, results_by_time: [ { total: { "UnblendedCost" => { amount: "4.5612", unit: "USD" } } } ])

      invoice, estimate = client.charges(today)
      expect(invoice).to have_attributes(external_id: "invoice:EUINBR26-1", competence: Date.new(2026, 10), due_on: Date.new(2026, 11, 2),
                                         currency: "USD", amount_cents: 1_234, replaces: [ "estimate:2026-10" ])
      expect(estimate).to have_attributes(external_id: "estimate:2026-11", status: :forecast, amount_cents: 456,
                                          competence: Date.new(2026, 11), due_on: Date.new(2026, 12, 3))
      expect(invoicing.api_requests.first[:params]).to include(selector: { resource_type: "ACCOUNT_ID", value: connection.account_id },
                                                                filter: { billing_period: { month: 11, year: 2026 } })
    end

    it "não consulta o Cost Explorer no dia 1º" do
      invoicing.stub_responses(:list_invoice_summaries, invoice_summaries: [])
      expect(client.charges(Date.new(2026, 11, 1))).to be_empty
      expect(cost_explorer.api_requests).to be_empty
    end
  end

  describe Billing::Cloudflare do
    let(:connection) { create(:billing_connection, provider: "cloudflare", account_id: "abc123") }
    let(:client) { described_class.new(connection, env: { "BILLING_CLOUDFLARE_API_TOKEN" => "cf-token" }) }

    it "transforma o histórico em cobranças, com o pagamento pelo valor a pagar" do
      requests = stub_graph(graph_response(200, { "success" => true, "result" => [
        { "id" => "h1", "type" => "charge", "action" => "subscription", "amount" => 20.0, "amount_to_pay" => 0, "currency" => "usd",
          "description" => "Pro Plan", "occurred_at" => "2026-11-01T12:00:00Z" },
        { "id" => "h2", "type" => "charge", "amount" => 5.0, "amount_to_pay" => 5.0, "currency" => "USD",
          "description" => "Workers Paid", "occurred_at" => "2026-11-05T12:00:00Z" },
        { "id" => "h3", "type" => "refund", "amount" => 5.0, "occurred_at" => "2026-11-06T12:00:00Z" }
      ] }))

      paid, open = client.charges(today)
      expect(paid).to have_attributes(external_id: "h1", status: :paid, paid_on: Date.new(2026, 11, 1), amount_cents: 2_000, currency: "USD",
                                      description: "Cloudflare — Pro Plan")
      expect(open).to have_attributes(external_id: "h2", status: :pending, paid_on: nil)
      expect(requests.first.path).to start_with("/client/v4/accounts/abc123/billing/history?")
      expect(requests.first["Authorization"]).to eq("Bearer cf-token")
    end

    it "explica o erro devolvido pela API" do
      stub_graph(graph_response(403, { "success" => false, "errors" => [ { "code" => 10_000, "message" => "Authentication error" } ] }))
      expect { client.charges(today) }.to raise_error(Billing::Error, "Cloudflare respondeu: Authentication error")
    end
  end

  describe Billing::Railway do
    let(:connection) { create(:billing_connection, provider: "railway", account_id: "0b5e8f6a-1c2d-4e3f-9a8b-7c6d5e4f3a2b") }
    let(:client) { described_class.new(connection, env: { "BILLING_RAILWAY_API_TOKEN" => "rw-token" }) }
    let(:cycle) { { "start" => "2026-10-18T16:10:38.000Z", "end" => "2026-11-18T16:10:38.000Z" } }

    def customer(invoices:, usage: 10.33)
      graph_response(200, { "data" => { "workspace" => { "customer" => { "currentUsage" => usage, "billingPeriod" => cycle,
                                                                         "invoices" => invoices } } } })
    end

    def invoice(id, total:, status:, from:, to:, reissued_of: nil)
      { "invoiceId" => id, "total" => total, "status" => status, "periodStart" => from, "periodEnd" => to, "reissuedInvoiceOf" => reissued_of }
    end

    it "lê as faturas do workspace e a estimativa do ciclo corrente" do
      requests = stub_graph(customer(invoices: [
        invoice("in_1", total: 1_373, status: "paid", from: "2026-09-18T16:10:38.000Z", to: "2026-10-18T16:10:38.000Z"),
        invoice("in_3", total: 1_200, status: "open", from: Time.utc(2026, 8, 18, 16, 10).to_i.to_s, to: Time.utc(2026, 9, 18, 16, 10).to_i.to_s,
                        reissued_of: "in_0"),
        invoice("in_v", total: 999, status: "void", from: "2026-07-18T16:10:38.000Z", to: "2026-08-18T16:10:38.000Z"),
        invoice("in_z", total: 0, status: "paid", from: "2026-06-18T16:10:38.000Z", to: "2026-07-18T16:10:38.000Z")
      ]))

      paid, reissued, estimate, *rest = client.charges(today)
      expect(rest).to be_empty
      expect(paid).to have_attributes(external_id: "invoice:in_1", competence: Date.new(2026, 9), due_on: Date.new(2026, 10, 18),
                                      currency: "USD", amount_cents: 1_373, status: :paid, paid_on: Date.new(2026, 10, 18),
                                      replaces: [ "estimate:2026-09-18" ], description: "Railway — fatura de 18/09 a 18/10/2026")
      expect(reissued).to have_attributes(status: :pending, due_on: Date.new(2026, 9, 18), replaces: [ "estimate:2026-08-18", "invoice:in_0" ])
      expect(estimate).to have_attributes(external_id: "estimate:2026-10-18", status: :forecast, amount_cents: 1_033,
                                          competence: Date.new(2026, 10), due_on: Date.new(2026, 11, 18))
      expect(requests.first["Authorization"]).to eq("Bearer rw-token")
      expect(json_body(requests.first)["variables"]).to eq("id" => connection.account_id)
    end

    it "não lança estimativa quando a fatura do ciclo já fechou" do
      stub_graph(customer(invoices: [ invoice("in_9", total: 2_000, status: "open", from: cycle["start"], to: cycle["end"]) ]))
      expect(client.charges(today).map(&:external_id)).to eq([ "invoice:in_9" ])
    end

    it "tenta o cabeçalho Team-Access-Token quando o Bearer não é aceito" do
      requests = stub_graph(graph_response(200, { "errors" => [ { "message" => "Workspace not found" } ] }), customer(invoices: []))
      expect(client.charges(today).map(&:external_id)).to eq([ "estimate:2026-10-18" ])
      expect(requests.last["Team-Access-Token"]).to eq("rw-token")
    end

    it "explica o erro devolvido pela API, o do Authorization quando os dois cabeçalhos falham" do
      stub_graph(graph_response(200, { "errors" => [ { "message" => "Workspace not found" } ] }),
                 graph_response(200, { "errors" => [ { "message" => "Not Authorized" } ] }))
      expect { client.charges(today) }.to raise_error(Billing::Error, "Railway respondeu: Workspace not found")
    end

    it "exige o ID do workspace" do
      expect(build(:billing_connection, provider: "railway", account_id: "Rafael Batista's Projects")).not_to be_valid
      expect(connection).to be_valid
    end
  end

  describe DomainExpirySync do
    it "registra a renovação vista no RDAP e não volta o vencimento" do
      renewed = create(:domain, name: "devbatista.com.br", expires_on: today + 10)
      odd = create(:domain, name: "outro.com", expires_on: today + 100)
      dates = { "devbatista.com.br" => today + 375, "outro.com" => today + 5 }
      expect(described_class.new(today, lookup: dates.method(:[])).run).to eq([ renewed ])
      expect(renewed.reload).to have_attributes(expires_on: today + 375, rdap_checked_at: be_present)
      expect(renewed.notes).to include("Renovação detectada no RDAP")
      expect(odd.reload.expires_on).to eq(today + 100)
    end
  end

  describe "Conexões de cobrança", type: :request do
    it "cadastra, lista e sincroniza pela tela do Financeiro" do
      supplier = create(:supplier, name: "Amazon Web Services")
      sign_in create(:user, :financeiro)
      post billing_connections_path, params: { billing_connection: { provider: "aws", name: "AWS DevBatista", supplier_id: supplier.id,
                                                                     account_id: "123456789012", cost_center_key: "area:Infraestrutura interna",
                                                                     auto_paid: "1" } }
      connection = BillingConnection.sole
      expect(response).to redirect_to(billing_connections_path)

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with(start_with("BILLING_AWS")).and_return(nil)
      get billing_connections_path
      expect(response.body).to include("AWS DevBatista", "Falta configurar", "BILLING_AWS_ACCESS_KEY_ID")

      allow(BillingConnection).to receive(:find).and_return(connection)
      allow(connection).to receive(:client).and_return(fake_client(charge))
      allow(connection).to receive(:missing_env).and_return([])
      post sync_billing_connection_path(connection)
      expect(flash[:notice]).to include("1 nova")
      expect(Payable.sole.description).to eq("AWS — fatura 1 (Outubro/2026)")
    end

    it "valida a conta da AWS e responde 403 para quem não acessa o Financeiro" do
      expect(build(:billing_connection, account_id: "123")).not_to be_valid
      sign_in create(:user, :comercial)
      get billing_connections_path
      expect(response).to have_http_status(:forbidden)
    end
  end
end
