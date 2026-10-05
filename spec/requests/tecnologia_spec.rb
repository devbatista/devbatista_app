require "rails_helper"

RSpec.describe "Tecnologia e Produtos" do
  let(:dev) { create(:user, :desenvolvedor) }
  let(:company) { create(:company, trade_name: "Empresa ACME") }

  before { ExchangeRate.create!(currency: "USD", quoted_on: Date.current, rate: 5.62) }

  describe "Aplicações" do
    it "lista e abre a aplicação com o mapa de dependências" do
      server = create(:server, company: company, name: "acme-worker-01")
      app = create(:app, company: company, name: "Portal ACME", url: "portal.acme.com.br", hosting_key: "Server:#{server.id}",
                         vault_reference: "Cofre DevBatista › Clientes › ACME › Portal ACME")
      create(:database, app: app, backup_policy: "Diário · 7 dias")
      create(:integration, app: app, platform: "Amazon SES")
      create(:domain, company: company, name: "acme.com.br", expires_on: Date.current + 7)
      sign_in dev
      get apps_path
      expect(response.body).to include("Portal ACME", "acme-worker-01", "portal.acme.com.br")
      get app_path(app)
      expect(response.body).to include("Mapa de dependências", "PostgreSQL 16.4", "Amazon SES", "acme.com.br", "Cofre DevBatista › Clientes › ACME › Portal ACME")
    end

    it "cadastra a aplicação e recusa credencial no lugar da referência" do
      sign_in dev
      post apps_path, params: { app: { company_id: company.id, name: "API Delta", environment: "production", status: "active", vault_reference: "token=abc123" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("parece conter uma senha, chave ou token")
      post apps_path, params: { app: { company_id: company.id, name: "API Delta", environment: "production", status: "active" } }
      expect(response).to redirect_to(app_path(App.find_by!(name: "API Delta")))
    end

    it "deixa o financeiro consultar, mas não cadastrar, e barra o comercial" do
      sign_in create(:user, :financeiro)
      get apps_path
      expect(response).to have_http_status(:ok)
      post apps_path, params: { app: { name: "X" } }
      expect(response).to have_http_status(:forbidden)
      sign_in create(:user, :comercial)
      get servers_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Servidores, bancos, integrações e serviços externos" do
    it "cadastra servidor e serviço externo e mostra o pago pela DevBatista" do
      supplier = create(:supplier, name: "AWS")
      sign_in dev
      post servers_path, params: { server: { company_id: company.id, supplier_id: supplier.id, name: "acme-worker-01", host: "18.231.44.12",
                                             environment: "production", monthly_cost: "220" } }
      expect(response).to redirect_to(servers_path)
      post external_services_path, params: { external_service: { name: "Railway", supplier_id: create(:supplier, name: "Railway").id, company_id: company.id,
                                                                 cost: "26,69", currency: "USD", periodicity: "monthly", paid_by: "devbatista" } }
      expect(response).to redirect_to(external_services_path)
      get external_services_path
      expect(response.body).to include("Pago pela DevBatista", "US$ 26,69/mês", "≈ R$ 150")
      get servers_path
      expect(response.body).to include("acme-worker-01", "R$ 220")
    end

    it "lista bancos e integrações" do
      app = create(:app, company: company, name: "Sistema ERP")
      create(:database, app: app, technology: "MySQL", environment: "staging")
      create(:integration, app: app, platform: "Mailgun", status: "configuring")
      sign_in dev
      get databases_path
      expect(response.body).to include("Sistema ERP", "MySQL", "Sem backup")
      get integrations_path
      expect(response.body).to include("Mailgun", "Em configuração")
    end
  end

  describe "Domínios" do
    it "destaca o domínio sem renovação automática e registra a renovação" do
      domain = create(:domain, company: company, name: "acme.com.br", expires_on: Date.current + 7, auto_renew: false)
      sign_in dev
      get domains_path
      expect(response.body).to include("acme.com.br vence em", "não tem renovação automática", "Registrar renovação")
      patch renewal_domain_path(domain), params: { renewal: { expires_on: Date.current + 372, cost: "40", auto_renew: "1" } }
      expect(domain.reload).to have_attributes(expires_on: Date.current + 372, auto_renew: true)
    end
  end

  describe "Produtos e assinaturas" do
    it "mostra produtos, indicadores e registra assinatura" do
      product = create(:product, name: "CatalystOps")
      create(:subscription, product: product, monthly_value_cents: 14_900)
      admin = create(:user, :admin)
      sign_in admin
      get products_path
      expect(response.body).to include("CatalystOps", "R$ 149")
      get product_indicators_path
      expect(response.body).to include("Indicadores dos produtos", "Comparação entre produtos")
      post subscriptions_path, params: { subscription: { product_id: product.id, subscriber_name: "Padaria Pão de Ouro", plan: "Essencial",
                                                         monthly_value: "49", started_on: Date.current, status: "active" } }
      expect(product.reload.mrr_cents).to eq(19_800)
    end

    it "deixa o comercial consultar, mas não cadastrar, e barra o suporte" do
      sign_in create(:user, :comercial)
      get products_path
      expect(response).to have_http_status(:ok)
      post products_path, params: { product: { name: "X" } }
      expect(response).to have_http_status(:forbidden)
      sign_in create(:user, :suporte)
      get subscriptions_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Visão 360º, busca e chamados" do
    it "mostra a aba Infraestrutura para quem acessa Tecnologia" do
      create(:app, company: company, name: "Portal ACME")
      create(:domain, company: company, name: "acme.com.br", expires_on: Date.current + 7, auto_renew: false)
      sign_in dev
      get company_path(company)
      expect(response.body).to include('data-tab="infraestrutura"', "Portal ACME", "acme.com.br vence em")
      sign_in create(:user, :comercial)
      get company_path(company)
      expect(response.body).not_to include('data-tab="infraestrutura"')
    end

    it "encontra aplicações na busca" do
      create(:app, company: company, name: "Portal ACME", url: "portal.acme.com.br")
      sign_in dev
      get search_path(q: "portal.acme", format: :json)
      expect(response.parsed_body.map { |g| g["label"] }).to include("Aplicações")
    end

    it "abre chamado com a aplicação afetada" do
      app = create(:app, company: company, name: "API Delta")
      sign_in create(:user, :suporte)
      post tickets_path, params: { ticket: { company_id: company.id, app_id: app.id, subject: "Fora do ar", description: "Erro 502", category: "infrastructure", priority: "high" } }
      expect(Ticket.last.app).to eq(app)
      follow_redirect!
      expect(response.body).to include("Aplicação afetada", "API Delta")
    end
  end
end
