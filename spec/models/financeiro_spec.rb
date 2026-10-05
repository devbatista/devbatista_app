require "rails_helper"

RSpec.describe "Financeiro" do
  let(:today) { Date.current }

  def usd(rate, on: today)
    ExchangeRate.create!(currency: "USD", quoted_on: on, rate: rate)
  end

  describe Receivable do
    it "nasce pendente, prevista se a competência é futura e vencida se já venceu" do
      expect(create(:receivable).status).to eq("pending")
      expect(create(:receivable, competence: today.next_month, due_on: today.next_month).status).to eq("forecast")
      expect(create(:receivable, due_on: today - 1).status).to eq("overdue")
    end

    it "fica paga com a data de pagamento e volta a pendente sem ela" do
      receivable = create(:receivable)
      receivable.register_payment!(paid_on: today)
      expect(receivable).to be_paid
      expect(receivable.paid_amount_cents).to eq(300_000)
      receivable.update!(paid_on: nil)
      expect(receivable).to be_pending
    end

    it "sugere a categoria pelo serviço e o contato principal para a cobrança" do
      company = create(:company)
      contact = create(:contact, company: company, primary: true)
      receivable = create(:receivable, company: company, category: nil, service: create(:service, name: "Hospedagem"))
      expect([ receivable.category, receivable.contact ]).to eq([ "Hospedagem", contact ])
    end

    it "calcula o atraso em dias" do
      expect(create(:receivable, due_on: today - 12).days_late).to eq(12)
    end

    it "mantém Faturamento = Recebido + A receber + Vencido, sem as canceladas" do
      create(:receivable, amount_cents: 300_000, paid_on: today - 1, due_on: today - 1)
      create(:receivable, amount_cents: 150_000)
      create(:receivable, amount_cents: 80_000, competence: today.next_month, due_on: today.next_month)
      create(:receivable, amount_cents: 120_000, due_on: today - 3)
      create(:receivable, amount_cents: 99_000).cancel!
      summary = Receivable.summary
      expect(summary[:billed]).to eq(summary[:paid] + summary[:open] + summary[:overdue])
      expect(summary).to include(billed: 650_000, paid: 300_000, open: 230_000, overdue: 120_000, billed_count: 4)
    end
  end

  describe Payable do
    it "exige área interna ou cliente como centro de custo e usa a categoria do fornecedor" do
      payable = build(:payable, cost_center: nil, category: nil, supplier: create(:supplier, category: "Software"))
      expect(payable).not_to be_valid
      expect(payable.errors[:cost_center]).to be_present
      payable.cost_center_key = "area:Operação"
      expect(payable).to be_valid
      expect(payable.category).to eq("Software")
    end

    it "estima em reais pela PTAX do dia e grava o valor definitivo na data do pagamento" do
      usd(5.62)
      usd(5.5, on: today - 1)
      payable = create(:payable, currency: "USD", original_amount: "20,00", amount_cents: nil)
      expect([ payable.amount_cents, payable.exchange_rate, payable ]).to match([ 11_240, BigDecimal("5.62"), be_estimated ])
      payable.register_payment!(paid_on: today - 1)
      expect([ payable.amount_cents, payable.exchange_rate, payable.status ]).to eq([ 11_000, BigDecimal("5.5"), "paid" ])
      expect(payable).not_to be_estimated
    end

    it "aceita o câmbio ou o valor em reais informados no pagamento" do
      usd(5.62)
      payable = create(:payable, currency: "USD", original_amount: 25, amount_cents: nil)
      payable.register_payment!(paid_on: today, rate: "5,70")
      expect(payable.amount_cents).to eq(14_250)
      other = create(:payable, currency: "USD", original_amount: 25, amount_cents: nil)
      other.register_payment!(paid_on: today, amount: "150,00")
      expect(other.amount_cents).to eq(15_000)
    end

    it "entra no custo direto do cliente quando ele é o centro de custo" do
      company = create(:company)
      create(:payable, cost_center_key: "company:#{company.id}", amount_cents: 22_000)
      create(:payable, cost_center_key: "company:#{company.id}", amount_cents: 9_000).cancel!
      create(:payable, amount_cents: 50_000)
      expect(company.direct_cost_cents(today.all_month)).to eq(22_000)
    end
  end

  describe ExchangeRate do
    it "busca a PTAX no Banco Central, guarda e usa a última conhecida se a API falhar" do
      allow(BcbPtax).to receive(:fetch).and_return({ quoted_on: today - 1, rate: BigDecimal("5.4321") })
      expect(ExchangeRate.rate_for("USD", today)).to eq(BigDecimal("5.4321"))
      expect(ExchangeRate.find_by(currency: "USD", quoted_on: today - 1)).to be_present
      allow(BcbPtax).to receive(:fetch).and_return(nil)
      Rails.cache.clear
      rate = ExchangeRate.lookup("USD", today + 3)
      expect([ rate.rate, rate.fallback ]).to eq([ BigDecimal("5.4321"), true ])
      expect(ExchangeRate.rate_for("BRL")).to eq(1)
    end

    it "lê o último boletim de fechamento da resposta da API Olinda" do
      body = { value: [ { cotacaoCompra: 5.40, cotacaoVenda: 5.41, dataHoraCotacao: "2026-09-16 13:09:27.453", tipoBoletim: "Fechamento" },
                        { cotacaoCompra: 5.61, cotacaoVenda: 5.6201, dataHoraCotacao: "2026-09-17 13:05:10.111", tipoBoletim: "Fechamento" },
                        { cotacaoCompra: 5.70, cotacaoVenda: 5.71, dataHoraCotacao: "2026-09-17 11:00:00.000", tipoBoletim: "Intermediário" } ] }.to_json
      response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(body)
      allow(Net::HTTP).to receive(:start).and_return(response)
      BcbPtax.enabled = true
      expect(BcbPtax.fetch("USD", Date.new(2026, 9, 17))).to eq(quoted_on: Date.new(2026, 9, 17), rate: BigDecimal("5.6201"))
    ensure
      BcbPtax.enabled = false
    end
  end

  describe RecurrenceRoutine do
    let(:today) { Date.new(2026, 9, 17) }
    let(:service) { create(:service, name: "Consultoria de TI") }
    let!(:customer_service) { create(:customer_service, service: service, price_cents: 300_000, start_date: Date.new(2026, 3, 12), due_day: 10) }

    before { allow(Date).to receive(:current).and_return(today) }

    it "gera os títulos até o horizonte de 3 meses, uma única vez por competência" do
      run = described_class.new(today).run!
      titles = customer_service.receivables.order(:due_on)
      expect(titles.map(&:due_on)).to eq([ Date.new(2026, 9, 10), Date.new(2026, 10, 10), Date.new(2026, 11, 10), Date.new(2026, 12, 10) ])
      expect(titles.map(&:status)).to eq(%w[overdue forecast forecast forecast])
      expect(titles.second.description).to eq("Consultoria de TI — Outubro/2026")
      expect(run).to have_attributes(generated_count: 4, overdue_count: 1, horizon_on: Date.new(2026, 12, 31))
      expect { described_class.new(today).run! }.not_to change(Receivable, :count)
    end

    it "respeita a periodicidade e o dia de vencimento" do
      quarterly = create(:customer_service, price_cents: 360_000, recurrence: "quarterly", start_date: Date.new(2026, 4, 15), due_day: 15)
      described_class.new(today).run!
      expect(quarterly.receivables.pluck(:due_on)).to eq([ Date.new(2026, 10, 15) ])
    end

    it "passa a Pendente quando chega o mês e avisa o financeiro do vencido, uma vez" do
      financeiro = create(:user, :financeiro)
      create(:user, :comercial)
      described_class.new(today).run!
      expect(Notification.where(kind: "receivable_overdue").map(&:user)).to contain_exactly(financeiro)
      allow(Date).to receive(:current).and_return(Date.new(2026, 10, 11))
      described_class.new(Date.new(2026, 10, 11)).run!
      october = customer_service.receivables.find_by(competence: Date.new(2026, 10, 1))
      expect(october).to be_overdue
      expect(Notification.where(kind: "receivable_overdue", user: financeiro).count).to eq(2)
    end

    it "muda só os títulos futuros não pagos quando o valor do serviço muda" do
      described_class.new(today).run!
      september = customer_service.receivables.find_by(competence: Date.new(2026, 9, 1))
      september.register_payment!(paid_on: today)
      customer_service.update!(price_cents: 350_000)
      amounts = customer_service.receivables.order(:due_on).pluck(:amount_cents)
      expect(amounts).to eq([ 300_000, 350_000, 350_000, 350_000 ])
    end

    it "cancela os títulos posteriores ao encerramento do serviço" do
      described_class.new(today).run!
      customer_service.update!(status: "ended", ended_on: Date.new(2026, 10, 31))
      expect(customer_service.receivables.order(:due_on).pluck(:status)).to eq(%w[overdue forecast cancelled cancelled])
    end

    it "gera as despesas recorrentes e estima as em dólar pela PTAX do dia" do
      ExchangeRate.create!(currency: "USD", quoted_on: today, rate: 5.62)
      rule = create(:recurring_expense, description: "Hospedagem — Sistema ERP", currency: "USD", amount_cents: 2_000, due_day: 18, start_on: Date.new(2026, 1, 18))
      described_class.new(today).run!
      payables = rule.payables.order(:due_on)
      expect(payables.map(&:due_on)).to eq([ Date.new(2026, 9, 18), Date.new(2026, 10, 18), Date.new(2026, 11, 18), Date.new(2026, 12, 18) ])
      expect(payables.first).to have_attributes(status: "pending", original_amount_cents: 2_000, amount_cents: 11_240)
      rule.update!(status: "ended", ended_on: Date.new(2026, 10, 31))
      expect(rule.payables.order(:due_on).pluck(:status)).to eq(%w[pending forecast cancelled cancelled])
    end

    it "não gera despesa em moeda estrangeira sem cotação e registra o aviso" do
      create(:recurring_expense, description: "GitHub", currency: "USD", amount_cents: 2_400, due_day: 8, start_on: Date.new(2026, 1, 8))
      run = described_class.new(today).run!
      expect(Payable.count).to eq(0)
      expect(run.warning_list.first).to include("Sem cotação do USD")
    end
  end

  describe Invoice do
    it "exige número e data de emissão quando emitida e aceita só PDF ou XML" do
      invoice = build(:invoice, number: nil, issued_on: nil)
      expect(invoice).not_to be_valid
      expect(invoice.errors.attribute_names).to include(:number, :issued_on)
      invoice = build(:invoice)
      invoice.files.attach(io: StringIO.new("x"), filename: "nota.png", content_type: "image/png")
      expect(invoice).not_to be_valid
      expect(build(:invoice, status: "pending", number: nil, issued_on: nil)).to be_valid
    end
  end

  describe Supplier do
    it "usa as categorias das despesas" do
      expect(build(:supplier, category: "Viagens")).not_to be_valid
      expect(build(:supplier, category: "Software")).to be_valid
    end
  end
end
