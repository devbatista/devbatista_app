require "rails_helper"

RSpec.describe "Tools do escritório de agentes no MCP" do
  let(:admin) { create(:user, :admin) }
  let(:sem_area) { create(:user, :comercial) }
  let(:leitor) { create(:user, role: create(:role, permissions: { "agentes" => "read" })) }
  let!(:sol) { create(:agent, key: "sol", name: "Sol", position: 2) }
  let!(:ops) { create(:agent, key: "ops", name: "Ops", position: 1) }

  def error_text(tool, user, **args)
    response = call_tool(tool, user, **args)
    expect(response).to be_error
    response.content.dig(0, :text)
  end

  it "as três estão registradas no endpoint" do
    expect(Mcp::Endpoint::TOOLS).to include(Mcp::Tools::RegistrarEvento, Mcp::Tools::LerPendencias, Mcp::Tools::ConcluirPendencia)
  end

  describe Mcp::Tools::RegistrarEvento do
    it "registra o evento do agente pela chave, com os dados, e audita como veio do Claude" do
      data = tool_data(described_class, admin, agente: "Sol", status: "done", titulo: "Leads qualificados",
                                               resumo: "3 de 5 qualificados.", dados: { qualificados: 3 })
      event = sol.events.sole
      expect(event).to have_attributes(status: "done", title: "Leads qualificados", summary: "3 de 5 qualificados.",
                                       needs_approval: false, payload: { "qualificados" => 3 })
      expect(data).to include("id" => event.id, "agente" => "sol", "status" => "done", "status_rotulo" => "Concluído", "decisao" => nil)
      expect(data["link"]).to end_with("/office?agente=sol")
      expect(AuditLog.where(auditable: event, action: "create", user: admin, area: "agentes")).to exist
    end

    it "com precisa_aprovacao, fica aguardando a decisão" do
      data = tool_data(described_class, admin, agente: "sol", status: "working", titulo: "Enviar follow-up", precisa_aprovacao: true)
      expect(data).to include("status" => "awaiting_approval", "precisa_aprovacao" => true, "decisao" => "pending", "decisao_rotulo" => "Pendente")
      expect(sol.reload.status).to eq("awaiting_approval")
    end

    it "recusa agente desconhecido ou inativo e diz as chaves ativas" do
      create(:agent, key: "velho", active: false)
      expect(error_text(described_class, admin, agente: "zeca", status: "working", titulo: "x")).to eq(
        'Agente "zeca" não encontrado ou inativo. Chaves ativas: ops, sol.'
      )
      expect(error_text(described_class, admin, agente: "velho", status: "working", titulo: "x")).to include("não encontrado ou inativo")
    end

    it "devolve o erro de validação para o Claude corrigir" do
      expect(error_text(described_class, admin, agente: "sol", status: "working", titulo: "x" * 121)).to start_with("Não foi possível salvar: Título")
    end

    it "recusa quem não tem a área ou só lê, sem revelar as chaves" do
      expect(error_text(described_class, sem_area, agente: "zeca", status: "working", titulo: "x")).to eq("Sem permissão para esta ação.")
      expect(error_text(described_class, leitor, agente: "sol", status: "working", titulo: "x")).to eq("Sem permissão para esta ação.")
      expect(AgentEvent.count).to eq(0)
    end
  end

  describe Mcp::Tools::LerPendencias do
    it "devolve as ordens pendentes e as decisões não lidas do agente, e marca as decisões como lidas" do
      order = create(:agent_order, agent: sol, user: admin, body: "Priorize o e-book")
      create(:agent_order, agent: sol, user: admin, status: "completed", response: "Feito", completed_at: 1.hour.ago)
      create(:agent_order, agent: ops, user: admin)
      approved = create(:agent_event, :approval, agent: sol, title: "Follow-up")
      approved.decide!("approved", by: admin, note: "Pode mandar")
      waiting = create(:agent_event, :approval, agent: sol, title: "Subir verba")

      data = tool_data(described_class, admin, agente: "sol")

      expect(data["ordens"].sole).to include("id" => order.id, "texto" => "Priorize o e-book", "status" => "pending", "por" => admin.name)
      expect(data["decisoes"].sole).to include("id" => approved.id, "decisao" => "approved", "decisao_rotulo" => "Aprovado", "observacao" => "Pode mandar")
      expect(data["aguardando_decisao"].sole).to include("id" => waiting.id, "decisao" => "pending")
      expect(approved.reload.decision_read_at).to be_present
      expect(order.reload.delivered_at).to be_present

      again = tool_data(described_class, admin, agente: "sol")
      expect(again["decisoes"]).to be_empty
      expect(again["ordens"].sole["id"]).to eq(order.id)
    end

    it "não regrava a primeira leitura da ordem" do
      order = create(:agent_order, agent: sol, user: admin, delivered_at: 2.hours.ago)
      expect { tool_data(described_class, admin, agente: "sol") }.not_to(change { order.reload.delivered_at })
    end

    it "avisa o escritório quando há algo lido" do
      create(:agent_order, agent: sol, user: admin)
      clear_enqueued_jobs
      tool_data(described_class, admin, agente: "sol")
      expect(Turbo::Streams::ActionBroadcastJob).to have_been_enqueued.exactly(3).times
    end

    it "recusa quem só lê a área (a leitura marca as decisões)" do
      expect(error_text(described_class, leitor, agente: "sol")).to eq("Sem permissão para esta ação.")
    end
  end

  describe Mcp::Tools::ConcluirPendencia do
    let!(:order) { create(:agent_order, agent: sol, user: admin) }

    it "conclui a ordem do agente com a resposta" do
      data = tool_data(described_class, admin, agente: "sol", ordem_id: order.id, resposta: "3 leads do e-book priorizados.")
      expect(order.reload).to have_attributes(status: "completed", response: "3 leads do e-book priorizados.")
      expect(data).to include("id" => order.id, "status" => "completed", "status_rotulo" => "Concluída", "resposta" => "3 leads do e-book priorizados.")
    end

    it "recusa ordem de outro agente, inexistente ou já concluída" do
      expect(error_text(described_class, admin, agente: "ops", ordem_id: order.id, resposta: "x")).to eq("Ordem não encontrada entre as do agente ops.")
      expect(error_text(described_class, admin, agente: "sol", ordem_id: "nao-e-uuid", resposta: "x")).to include("não encontrada")
      order.complete!("Feito")
      expect(error_text(described_class, admin, agente: "sol", ordem_id: order.id, resposta: "x")).to start_with("Esta ordem já foi concluída em")
    end

    it "recusa resposta vazia" do
      expect(error_text(described_class, admin, agente: "sol", ordem_id: order.id, resposta: "")).to start_with("Não foi possível salvar")
      expect(order.reload).to be_status_pending
    end
  end
end
