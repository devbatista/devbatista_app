require "rails_helper"

RSpec.describe "Clientes" do
  let(:admin) { create(:user, :admin) }
  let(:dev) { create(:user, :desenvolvedor) }
  let!(:company) { create(:company, trade_name: "Empresa ACME") }

  describe "Empresas" do
    it "lista e abre a Visão 360º" do
      create(:contact, company: company, name: "Marcos Andrade", primary: true)
      create(:customer_service, company: company, price_cents: 380_000)
      sign_in admin
      get companies_path
      expect(response.body).to include("Empresa ACME", "Marcos Andrade", "R$ 3.800")
      get company_path(company)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Visão 360º do cliente", "Total recorrente (MRR)")
    end

    it "cadastra a empresa e volta com erro quando o CNPJ é inválido" do
      sign_in admin
      post companies_path, params: { company: { legal_name: "Nova Ltda", trade_name: "Nova", cnpj: "11.222.333/0001-82", status: "prospect" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("CNPJ não é um CNPJ válido")

      post companies_path, params: { company: { legal_name: "Nova Ltda", trade_name: "Nova", cnpj: "11.222.333/0001-81", status: "prospect" } }
      expect(response).to redirect_to(company_path(Company.find_by!(trade_name: "Nova")))
    end

    it "deixa o desenvolvedor consultar, mas não cadastrar" do
      sign_in dev
      get companies_path
      expect(response).to have_http_status(:ok)
      post companies_path, params: { company: { legal_name: "X", trade_name: "X", cnpj: "11.222.333/0001-81" } }
      expect(response).to have_http_status(:forbidden)
    end

    it "esconde as abas de contratos para quem não tem acesso" do
      sign_in dev
      get company_path(company)
      expect(response.body).not_to include('data-tab="contratos"')
      expect(response.body).to include('data-tab="atividades"')
    end
  end

  describe "Contatos" do
    it "troca o contato principal" do
      current = create(:contact, company: company, primary: true)
      other = create(:contact, company: company)
      sign_in admin
      patch make_primary_contact_path(other)
      expect(other.reload.primary?).to be(true)
      expect(current.reload.primary?).to be(false)
    end
  end

  describe "Serviços contratados" do
    it "usa o preço padrão do catálogo quando o valor fica em branco" do
      service = create(:service, default_price_cents: 250_000)
      sign_in admin
      post customer_services_path, params: { customer_service: { company_id: company.id, service_id: service.id, recurrence: "monthly", start_date: Date.current, status: "active" } }
      expect(CustomerService.last.price_cents).to eq(250_000)
      expect(company.reload.mrr_cents).to eq(250_000)
    end
  end

  describe "Contratos" do
    it "lista e mostra o contrato" do
      contract = create(:contract, company: company, title: "Consultoria de TI")
      sign_in admin
      get contracts_path
      expect(response.body).to include("Consultoria de TI")
      get contract_path(contract)
      expect(response.body).to include("Alertas de vencimento")
    end

    it "responde 403 para o desenvolvedor, que não acessa contratos" do
      sign_in dev
      get contracts_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Documentos" do
    it "envia o arquivo ligado ao contrato com o autor automático" do
      contract = create(:contract, company: company)
      sign_in admin
      post documents_path, params: { document: { kind: "contract", documentable_type: "Contract", documentable_id: contract.id,
                                                 file: fixture_file_upload(Rails.root.join("public/icon.png"), "image/png") } }
      document = Document.last
      expect(response).to redirect_to(contract_path(contract))
      expect(document.uploaded_by).to eq(admin)
      expect(document.company).to eq(company)
      expect(document.title).to eq("icon.png")
    end

    it "envia documento interno, sem vínculo, e o encontra pelo filtro Sem cliente" do
      sign_in admin
      post documents_path, params: { document: { kind: "other", documentable_type: "Company", documentable_id: "",
                                                 file: fixture_file_upload(Rails.root.join("public/icon.png"), "image/png") } }
      document = Document.last
      expect(response).to redirect_to(documents_path)
      expect(document.documentable).to be_nil
      expect(document.documentable_type).to be_nil
      expect(document.company).to be_nil

      get documents_path(empresa: "nenhum")
      expect(response.body).to include("icon.png", "Sem vínculo")
    end

    it "não aceita vínculo com tipo desconhecido" do
      sign_in admin
      post documents_path, params: { document: { kind: "other", documentable_type: "User", documentable_id: admin.id,
                                                 file: fixture_file_upload(Rails.root.join("public/icon.png"), "image/png") } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
