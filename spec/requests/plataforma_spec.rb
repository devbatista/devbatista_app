require "rails_helper"

RSpec.describe "Busca, notificações e configurações" do
  let(:admin) { create(:user, :admin) }

  describe "Busca global" do
    before do
      company = create(:company, trade_name: "Empresa ACME")
      create(:contract, company: company, title: "Consultoria ACME")
    end

    it "agrupa os resultados por tipo" do
      sign_in admin
      get search_path(q: "acme", format: :json)
      expect(response.parsed_body.map { |g| g["label"] }).to eq(%w[Clientes Contratos])
    end

    it "só mostra o que o perfil pode ver" do
      sign_in create(:user, :desenvolvedor)
      get search_path(q: "acme", format: :json)
      expect(response.parsed_body.map { |g| g["label"] }).to eq(%w[Clientes])
    end
  end

  describe "Notificações" do
    it "marca como lida e abre o registro" do
      notification = Notification.create!(user: admin, kind: "contract_expiring", title: "Contrato vence", area: "contratos", path: "/contracts")
      sign_in admin
      patch notification_path(notification)
      expect(response).to redirect_to("/contracts")
      expect(notification.reload.read?).to be(true)
    end

    it "salva as preferências de e-mail do próprio usuário" do
      sign_in admin
      patch preferences_notifications_path, params: { email_kinds: [] }
      expect(admin.reload.email_for?("contract_expiring")).to be(false)
    end

    it "não deixa abrir a notificação de outra pessoa" do
      notification = Notification.create!(user: create(:user), kind: "contract_expiring", title: "X", area: "contratos")
      sign_in admin
      patch notification_path(notification)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Configurações" do
    it "salva os prazos de alerta, em ordem decrescente" do
      sign_in admin
      patch admin_settings_path, params: { aba: "alertas", settings: { contract_alert_days: %w[15 90 30] } }
      expect(Setting[:contract_alert_days]).to eq([ 90, 30, 15 ])
    end

    it "salva o CNPJ da empresa só com os dígitos e recusa um inválido" do
      cnpj = CnpjHelper.generate(42)
      sign_in admin
      patch admin_settings_path, params: { aba: "geral", settings: { company_cnpj: CnpjValidator.format(cnpj) } }
      expect(Setting[:company_cnpj]).to eq(cnpj)

      get admin_settings_path
      expect(response.body).to include('data-mask="cnpj"', CnpjValidator.format(cnpj))

      patch admin_settings_path, params: { aba: "geral", settings: { company_cnpj: "12.345.678/0001-00" } }
      expect(flash[:alert]).to include("CNPJ")
      expect(Setting[:company_cnpj]).to eq(cnpj)
    end

    it "salva o WhatsApp da empresa só com os dígitos" do
      sign_in admin
      patch admin_settings_path, params: { aba: "geral", settings: { company_whatsapp: "(11) 98765-4321" } }
      expect(Setting[:company_whatsapp]).to eq("11987654321")

      get admin_settings_path
      expect(response.body).to include('data-mask="phone"', "(11) 98765-4321")

      patch admin_settings_path, params: { aba: "geral", settings: { company_whatsapp: "+55 11 3456-7890" } }
      expect(Setting[:company_whatsapp]).to eq("1134567890")
    end

    it "expira a sessão pelo tempo sem uso configurado" do
      sign_in admin
      patch admin_settings_path, params: { aba: "geral", settings: { session_timeout_minutes: "60" } }
      expect(Setting[:session_timeout_minutes]).to eq(60)

      travel 45.minutes
      get root_path
      expect(response).to have_http_status(:ok)

      travel 61.minutes
      get root_path
      follow_redirect!
      expect(response).to redirect_to(new_user_session_path)
    end

    it "mantém o tempo de sessão dentro do limite" do
      Setting[:session_timeout_minutes] = 1
      expect(admin.timeout_in).to eq(5.minutes)
      Setting[:session_timeout_minutes] = 10_000
      expect(admin.timeout_in).to eq(12.hours)
    end

    it "responde 403 para quem não administra" do
      sign_in create(:user, :financeiro)
      patch admin_settings_path, params: { settings: { proposal_alert_days: "5" } }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
