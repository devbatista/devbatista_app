require "rails_helper"

RSpec.describe "Tools de leitura do MCP" do
  let(:admin) { create(:user) }

  describe Mcp::Tools::BuscarEmpresas do
    it "busca por nome e traz o contato principal" do
      company = create(:company, trade_name: "Transportes Lima")
      create(:contact, company: company, name: "Ana", email: "ana@lima.com", primary: true)
      create(:company, trade_name: "Outra")
      data = tool_data(described_class, admin, termo: "lima")
      expect(data["empresas"].size).to eq(1)
      expect(data["empresas"].first).to include("id" => company.id, "contato_principal" => include("nome" => "Ana"))
    end
  end

  describe Mcp::Tools::BuscarLeads do
    it "filtra por termo, status e só abertos, com paginação" do
      create(:lead, company_name: "Padaria Sol", status: "new")
      create(:lead, company_name: "Padaria Lua", status: "lost", lost_reason: "Preço")
      create(:lead, company_name: "Oficina", status: "contacted")

      data = tool_data(described_class, admin, termo: "padaria", so_abertos: true)
      expect(data["leads"].pluck("empresa")).to eq([ "Padaria Sol" ])

      data = tool_data(described_class, admin, status: %w[new contacted], por_pagina: 1)
      expect(data["paginacao"]).to include("total" => 2, "paginas" => 2, "por_pagina" => 1)
      expect(data["leads"].size).to eq(1)
    end

    it "mostra a quem é 'só os próprios' apenas os leads dele" do
      dono = create(:user, role: create(:role, key: "sdr", name: "SDR", permissions: { "comercial" => "own" }))
      create(:lead, user: dono, name: "Meu")
      create(:lead, name: "De outro")
      expect(tool_data(described_class, dono)["leads"].pluck("nome")).to eq([ "Meu" ])
    end
  end

  describe Mcp::Tools::VerLead do
    it "traz interações, oportunidades e propostas do lead" do
      lead = create(:lead, notes: "Indicado pelo João")
      create(:interaction, subject: lead, user: admin, kind: "call", notes: "Ligou pedindo orçamento", occurred_on: Date.current)
      create(:opportunity, lead: lead, title: "Site novo")
      create(:proposal, lead: lead, company: nil, title: "Proposta do site")

      data = tool_data(described_class, admin, id: lead.id)
      expect(data).to include("observacoes" => "Indicado pelo João", "link" => end_with("/commercial/leads/#{lead.id}"))
      expect(data["interacoes"].first).to include("tipo" => "call", "notas" => "Ligou pedindo orçamento")
      expect(data["oportunidades"].pluck("titulo")).to eq([ "Site novo" ])
      expect(data["propostas"].pluck("titulo")).to eq([ "Proposta do site" ])
    end
  end

  describe Mcp::Tools::Pipeline do
    it "agrupa leads e oportunidades por etapa, com valores" do
      create(:lead, status: "contacted")
      create(:opportunity, stage: "proposal", estimated_value_cents: 1_000_000)
      create(:opportunity, stage: "won", closed_on: Date.current, estimated_value_cents: 500_000)

      data = tool_data(described_class, admin)
      etapas = data["etapas"].index_by { |etapa| etapa["etapa"] }
      expect(etapas["contacted"]["quantidade"]).to eq(1)
      expect(etapas["proposal"]).to include("quantidade" => 1, "valor_total" => 10_000.0, "valor_ponderado" => 5_000.0)
      expect(data["indicadores"]).to include("fechado_no_mes" => 5_000.0, "negocios_abertos" => 2)
    end
  end

  describe Mcp::Tools::BuscarOportunidades do
    it "filtra por etapa e empresa" do
      company = create(:company)
      create(:opportunity, company: company, title: "Portal", stage: "negotiation")
      create(:opportunity, company: company, title: "App", stage: "meeting")
      create(:opportunity, title: "De outra empresa", stage: "negotiation")

      data = tool_data(described_class, admin, empresa_id: company.id, etapa: [ "negotiation" ])
      expect(data["oportunidades"].pluck("titulo")).to eq([ "Portal" ])
    end
  end

  describe Mcp::Tools::VerOportunidade do
    it "traz interações e propostas" do
      opportunity = create(:opportunity)
      create(:interaction, subject: opportunity, user: admin, kind: "meeting", notes: "Reunião de escopo", occurred_on: Date.current)
      create(:proposal, opportunity: opportunity, company: opportunity.company)

      data = tool_data(described_class, admin, id: opportunity.id)
      expect(data["interacoes"].first["tipo"]).to eq("meeting")
      expect(data["propostas"].size).to eq(1)
    end
  end

  describe Mcp::Tools::BuscarPropostas do
    it "busca pelo código e filtra só as abertas" do
      proposal = create(:proposal, title: "Portal")
      create(:proposal, title: "Antiga", status: "rejected", rejection_reason: "Preço")

      expect(tool_data(described_class, admin, termo: proposal.code.delete("#"))["propostas"].pluck("id")).to eq([ proposal.id ])
      expect(tool_data(described_class, admin, so_abertas: true)["propostas"].pluck("titulo")).to eq([ "Portal" ])
    end
  end

  describe Mcp::Tools::VerProposta do
    it "traz os itens, o total e o MRR" do
      proposal = create(:proposal)
      data = tool_data(described_class, admin, id: proposal.id)
      expect(data).to include("total" => 3_000.0, "mrr" => 3_000.0, "status" => "draft")
      expect(data["itens"].first).to include("recorrencia" => "monthly", "preco" => 3_000.0)
    end
  end
end
