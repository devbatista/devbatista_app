require "rails_helper"

RSpec.describe "Tecnologia e Produtos" do
  def usd(rate)
    ExchangeRate.create!(currency: "USD", quoted_on: Date.current, rate: rate)
  end

  describe "credenciais" do
    it "nenhum model de Tecnologia tem coluna de senha, chave ou token" do
      forbidden = /password|passwd|senha|secret|token|api_key|apikey|chave|private_key|credential|ssh_key/i
      [ App, Server, Database, Integration, ExternalService, Domain ].each do |model|
        expect(model.column_names.grep(forbidden)).to be_empty, "#{model.name} tem coluna suspeita: #{model.column_names.grep(forbidden)}"
      end
    end

    it "recusa credencial colada em referência ao cofre ou observações e aceita o caminho do cofre" do
      server = build(:server, vault_reference: "senha: S3nh@Forte")
      expect(server).not_to be_valid
      expect(server.errors[:vault_reference].first).to include("referência ao cofre")
      expect(build(:integration, notes: "chave sk-abcdefghijklmnopqrstuvwxyz123")).not_to be_valid
      expect(build(:server, vault_reference: "Cofre DevBatista › Clientes › ACME › SSH acme-worker-01")).to be_valid
    end
  end

  describe App do
    it "aponta a hospedagem para um servidor ou um serviço externo" do
      server = create(:server)
      app = create(:app, company: server.company, hosting_key: "Server:#{server.id}")
      expect(app.hosting).to eq(server)
      service = create(:external_service, company: app.company)
      app.update!(hosting_key: "ExternalService:#{service.id}")
      expect(app.reload.hosting).to eq(service)
      app.update!(hosting_key: "")
      expect(app.reload.hosting).to be_nil
    end

    it "soma o custo mensal pago pela DevBatista e acha o domínio pela URL" do
      usd(5.62)
      company = create(:company)
      server = create(:server, company: company, monthly_cost_cents: 22_000)
      app = create(:app, company: company, hosting_key: "Server:#{server.id}", url: "https://portal.acme.com.br")
      create(:external_service, company: company, app: app, cost_cents: 2_135)
      create(:external_service, company: company, app: app, cost_cents: 3_500, paid_by: "client")
      domain = create(:domain, company: company, name: "acme.com.br")
      create(:domain, company: company, name: "lojaacme.com.br")
      expect(app.monthly_cost_cents).to eq(22_000 + 11_999)
      expect(app.domain).to eq(domain)
    end
  end

  describe ExternalService do
    it "converte para reais pela PTAX e mensaliza o anual" do
      usd(5.62)
      expect(build(:external_service, cost_cents: 2_000).monthly_brl_cents).to eq(11_240)
      expect(build(:external_service, cost_cents: 9_900, periodicity: "annual").monthly_brl_cents).to eq(4_637)
      expect(build(:external_service, currency: "BRL", cost_cents: 15_000).monthly_brl_cents).to eq(15_000)
    end

    it "só entra no custo direto do cliente quando a DevBatista paga" do
      usd(5.0)
      company = create(:company)
      create(:server, company: company, monthly_cost_cents: 10_000)
      create(:external_service, company: company, cost_cents: 2_000)
      create(:external_service, company: company, cost_cents: 9_000, paid_by: "client")
      create(:external_service, company: company, cost_cents: 5_000, active: false)
      create(:domain, company: company, paid_by: "devbatista", renewal_cost_cents: 12_000)
      create(:domain, company: company, paid_by: "client", renewal_cost_cents: 4_000)
      expect(company.infrastructure_cost_cents).to eq(10_000 + 10_000 + 1_000)
    end
  end

  describe Domain do
    it "normaliza o nome e calcula a faixa de alerta" do
      domain = create(:domain, name: "https://www.ACME.com.br/", expires_on: Date.current + 7)
      expect(domain.name).to eq("acme.com.br")
      expect(domain.alert_window).to eq(7)
      expect(build(:domain, expires_on: Date.current + 45).alert_window).to eq(60)
      expect(build(:domain, expires_on: Date.current + 90).alert_window).to be_nil
    end

    it "registra a renovação" do
      domain = create(:domain, expires_on: Date.current + 7)
      domain.renew!(expires_on: Date.current + 372, cost: "45,00", auto_renew: true)
      expect(domain.reload).to have_attributes(expires_on: Date.current + 372, renewal_cost_cents: 4_500, auto_renew: true)
    end
  end

  describe DomainAlertsJob do
    let(:today) { Date.new(2026, 9, 17) }

    it "avisa Desenvolvedor e Administrador nos marcos de 60, 30 e 7 dias, uma vez por marco" do
      dev = create(:user, :desenvolvedor)
      admin = create(:user, :admin)
      create(:user, :financeiro)
      urgent = create(:domain, name: "acme.com.br", expires_on: today + 7, auto_renew: false)
      soon = create(:domain, name: "orion.app", expires_on: today + 49, auto_renew: true)
      create(:domain, name: "xyz.com.br", expires_on: today + 76)
      expect { 2.times { described_class.perform_now(today) } }.to change(Notification, :count).by(4)
      expect(Notification.where(notifiable: urgent).map(&:user)).to contain_exactly(dev, admin)
      expect(Notification.find_by(notifiable: urgent)).to have_attributes(level: "crit", title: include("sem renovação automática"))
      expect(Notification.find_by(notifiable: soon).level).to eq("warn")
    end
  end

  describe Product do
    it "calcula MRR, clientes e margem pelas assinaturas ativas e o custo do mês" do
      product = create(:product)
      create(:subscription, product: product, monthly_value_cents: 14_900)
      create(:subscription, product: product, monthly_value_cents: 7_900, started_on: Date.current.beginning_of_month)
      create(:subscription, product: product, monthly_value_cents: 4_900, status: "trial")
      create(:subscription, product: product, monthly_value_cents: 7_900, status: "cancelled", cancelled_on: Date.current << 2)
      product.update!(monthly_cost: "64,00")
      expect([ product.mrr_cents, product.clients_count ]).to eq([ 22_800, 2 ])
      expect(product.margin_percent).to eq(71.9)
      # No fim do mês passado: só a assinatura de 90 dias (a nova começou neste mês e a cancelada saiu antes).
      expect(product.mrr_cents(Date.current.prev_month.end_of_month)).to eq(14_900)
    end

    it "guarda o custo mês a mês" do
      product = create(:product)
      product.costs.create!(month: Date.current << 2, amount_cents: 30_000)
      product.update!(monthly_cost: "390")
      expect(product.monthly_cost_cents).to eq(39_000)
      expect(product.monthly_cost_cents((Date.current << 1).end_of_month)).to eq(30_000)
    end
  end

  describe Subscription do
    it "registra a data de cancelamento" do
      subscription = create(:subscription)
      subscription.update!(status: "cancelled")
      expect(subscription.cancelled_on).to eq(Date.current)
    end
  end

  describe "ligações com os outros módulos" do
    it "exige que a aplicação afetada do chamado seja do cliente" do
      ticket = build(:ticket, app: create(:app))
      expect(ticket).not_to be_valid
      expect(ticket.errors[:app]).to be_present
    end

    it "liga a conta a pagar recorrente ao serviço externo" do
      allow(Date).to receive(:current).and_return(Date.new(2026, 9, 17))
      ExchangeRate.create!(currency: "USD", quoted_on: Date.current, rate: 5.62)
      service = create(:external_service)
      rule = create(:recurring_expense, currency: "USD", amount_cents: 2_669, due_day: 18, start_on: Date.new(2026, 9, 18), external_service: service,
                                        company: service.company, cost_center: nil)
      RecurrenceRoutine.new(Date.current).run!
      expect(rule.payables.pluck(:external_service_id).uniq).to eq([ service.id ])
    end
  end
end
