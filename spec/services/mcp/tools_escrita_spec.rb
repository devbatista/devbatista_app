require "rails_helper"

RSpec.describe "Tools de escrita do MCP" do
  let(:admin) { create(:user) }
  let(:leitor) { create(:user, :financeiro) } # comercial só leitura

  def error_text(tool, user, **args)
    response = call_tool(tool, user, **args)
    expect(response).to be_error
    response.content.dig(0, :text)
  end

  describe Mcp::Tools::CriarLeads do
    let(:service) { create(:service) }

    it "cadastra em lote com os padrões, em nome de quem chamou, e audita" do
      data = tool_data(described_class, admin,
                       leads: [ { nome: "Ana", empresa: "Padaria Sol", email: "ANA@sol.com" }, { nome: "Oficina do Zé" } ],
                       padroes: { origem: "outbound", servico_id: service.id })
      expect(data).to include("gravados" => 2, "simulacao" => false)
      lead = Lead.find_by!(email: "ana@sol.com")
      expect(lead).to have_attributes(origin: "outbound", service: service, user: admin, status: "new", entered_on: Date.current)
      expect(AuditLog.where(auditable: lead, action: "create", user: admin)).to exist
    end

    it "simula sem gravar" do
      data = tool_data(described_class, admin, leads: [ { nome: "Ana", origem: "site" } ], simular: true)
      expect(data).to include("simulacao" => true, "gravados" => 0)
      expect(data["leads"].size).to eq(1)
      expect(Lead.count).to eq(0)
    end

    it "pula duplicados por e-mail ou nome, inclusive dentro da própria lista" do
      existing = create(:lead, name: "Ana", company_name: "Padaria Sol", email: "ana@sol.com")
      data = tool_data(described_class, admin, padroes: { origem: "site" },
                                               leads: [ { nome: "Ana Souza", email: "ana@sol.com" }, { nome: "Padaria sól" },
                                                        { nome: "Nova" }, { nome: "nova" } ])
      expect(data["gravados"]).to eq(1)
      expect(data["pulados_por_duplicidade"].pluck("linha")).to eq([ 1, 2, 4 ])
      expect(data["pulados_por_duplicidade"].first["ja_cadastrado"]["id"]).to eq(existing.id)
    end

    it "não grava nada se um lead for inválido e diz qual" do
      text = error_text(described_class, admin, leads: [ { nome: "Ana", origem: "site" }, { nome: "Sem origem" } ])
      expect(text).to start_with("Lead 2 (Sem origem):")
      expect(Lead.count).to eq(0)
    end

    it "recusa quem só lê o comercial" do
      expect(error_text(described_class, leitor, leads: [ { nome: "Ana", origem: "site" } ])).to eq("Sem permissão para esta ação.")
    end
  end

  describe Mcp::Tools::AtualizarLead do
    it "altera só os campos enviados e limpa com null" do
      lead = create(:lead, phone: "11 9999-0000", next_step: "Ligar")
      tool_data(described_class, admin, id: lead.id, proximo_passo: "Enviar proposta", proximo_passo_em: "2026-11-05", telefone: nil)
      expect(lead.reload).to have_attributes(next_step: "Enviar proposta", next_step_on: Date.new(2026, 11, 5), phone: nil,
                                             company_name: "Empresa do lead")
    end

    it "pede ao menos um campo" do
      expect(error_text(described_class, admin, id: create(:lead).id)).to eq("Envie ao menos um campo para alterar.")
    end
  end

  describe Mcp::Tools::MoverLead do
    it "move o lead em aberto" do
      lead = create(:lead)
      tool_data(described_class, admin, id: lead.id, status: "qualified")
      expect(lead.reload).to be_status_qualified
    end

    it "não move lead perdido" do
      lead = create(:lead, status: "lost", lost_reason: "Preço")
      expect(error_text(described_class, admin, id: lead.id, status: "new")).to include("perdido")
    end
  end

  describe Mcp::Tools::MarcarPerdido do
    it "marca a oportunidade como perdida com motivo da lista" do
      opportunity = create(:opportunity)
      tool_data(described_class, admin, tipo: "oportunidade", id: opportunity.id, motivo: "Sem orçamento", detalhes: "Ficou para 2027")
      expect(opportunity.reload).to have_attributes(stage: "lost", lost_reason: "Sem orçamento", lost_details: "Ficou para 2027")
    end

    it "recusa motivo fora da lista" do
      lead = create(:lead)
      expect(error_text(described_class, admin, tipo: "lead", id: lead.id, motivo: "Sumiu")).to include("não está na lista de motivos")
      expect(lead.reload).to be_status_new
    end
  end

  describe Mcp::Tools::RegistrarInteracao do
    it "registra no lead em nome de quem chamou" do
      lead = create(:lead)
      tool_data(described_class, admin, tipo_registro: "lead", id: lead.id, tipo: "whatsapp", notas: "Pediu proposta")
      expect(lead.interactions.sole).to have_attributes(kind: "whatsapp", user: admin, occurred_on: Date.current)
    end
  end

  describe Mcp::Tools::ConverterLead do
    it "cria empresa, contato e oportunidade com os dados do lead" do
      service = create(:service, name: "Site", default_price_cents: 800_000)
      lead = create(:lead, name: "Ana", company_name: "Padaria Sol", service: service, status: "qualified")
      data = tool_data(described_class, admin, id: lead.id, cnpj: "11.222.333/0001-81")

      company = Company.find(data["empresa"]["id"])
      expect(company).to have_attributes(trade_name: "Padaria Sol", status: "prospect")
      expect(company.contacts.sole.name).to eq("Ana")
      expect(data["oportunidade"]).to include("titulo" => "Site", "valor_estimado" => 8_000.0, "etapa" => "meeting")
      expect(lead.reload).to be_status_converted
    end

    it "exige CNPJ para empresa nova e não converte" do
      lead = create(:lead)
      expect(error_text(described_class, admin, id: lead.id)).to start_with("Não foi possível converter:")
      expect(lead.reload).to be_status_new
    end
  end

  describe Mcp::Tools::CriarOportunidade do
    it "cria na etapa Reunião com a probabilidade sugerida" do
      company = create(:company)
      data = tool_data(described_class, admin, titulo: "App de pedidos", empresa_id: company.id, valor_estimado: 25_000)
      expect(Opportunity.find(data["id"])).to have_attributes(stage: "meeting", probability: 25, estimated_value_cents: 2_500_000, user: admin)
    end

    it "explica a empresa inexistente" do
      expect(error_text(described_class, admin, titulo: "X", empresa_id: SecureRandom.uuid)).to start_with("Não foi possível salvar:")
    end
  end

  describe Mcp::Tools::AtualizarOportunidade do
    it "altera valor e próximo passo" do
      opportunity = create(:opportunity)
      tool_data(described_class, admin, id: opportunity.id, valor_estimado: 12_000.5, proximo_passo: "Reunião técnica")
      expect(opportunity.reload).to have_attributes(estimated_value_cents: 1_200_050, next_step: "Reunião técnica")
    end
  end

  describe Mcp::Tools::MoverOportunidade do
    it "fecha a oportunidade sem criar contrato" do
      opportunity = create(:opportunity, stage: "negotiation")
      tool_data(described_class, admin, id: opportunity.id, etapa: "won")
      expect(opportunity.reload).to have_attributes(stage: "won", probability: 100, closed_on: Date.current)
      expect(Contract.count).to eq(0)
    end

    it "não move oportunidade perdida" do
      opportunity = create(:opportunity, stage: "lost", lost_reason: "Preço")
      expect(error_text(described_class, admin, id: opportunity.id, etapa: "meeting")).to include("perdida")
    end
  end

  describe Mcp::Tools::CriarProposta do
    it "cria rascunho com a empresa da oportunidade e preço padrão do serviço" do
      opportunity = create(:opportunity)
      contact = create(:contact, company: opportunity.company, primary: true)
      project = create(:service, default_price_cents: 450_000, kind: "project")
      support = create(:service, kind: "recurring")
      data = tool_data(described_class, admin, titulo: "Portal", oportunidade_id: opportunity.id,
                                               itens: [ { servico_id: project.id }, { servico_id: support.id, preco: 1_000, recorrencia: "annual" } ])

      proposal = Proposal.find(data["id"])
      expect(proposal).to have_attributes(status: "draft", company: opportunity.company, contact: contact, user: admin,
                                          valid_until: Date.current + 15, total_cents: 550_000)
      expect(proposal.items.map { |item| [ item.recurrence, item.price_cents ] }).to eq([ [ "one_off", 450_000 ], [ "annual", 100_000 ] ])
    end

    it "recusa serviço inativo" do
      service = create(:service, status: "inactive")
      text = error_text(described_class, admin, titulo: "X", empresa_id: create(:company).id, itens: [ { servico_id: service.id } ])
      expect(text).to eq("Item 1: serviço não encontrado ou inativo no catálogo.")
    end

    it "exige destinatário" do
      expect(error_text(described_class, admin, titulo: "X", itens: [ { servico_id: create(:service).id } ])).to include("destinatário")
    end
  end

  describe Mcp::Tools::GerarPdfProposta do
    it "devolve os links do PDF" do
      proposal = create(:proposal)
      data = tool_data(described_class, admin, id: proposal.id)
      expect(data["baixar"]).to end_with("/commercial/proposals/#{proposal.id}/pdf?baixar=1")
      expect(data["arquivo"]).to eq("proposta-#{proposal.code.delete('#')}.pdf")
    end
  end
end
