require "rails_helper"

RSpec.describe "Servidor MCP" do
  let!(:admin) { create(:user) }

  def mcp(method, params = {}, token: "token-de-teste")
    headers = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
    headers["Authorization"] = "Bearer #{token}" if token
    post mcp_path, params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, headers: headers
  end

  def tool_result
    response.parsed_body.fetch("result")
  end

  it "recusa requisição sem token com 401 e WWW-Authenticate" do
    mcp("tools/list", token: nil)
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to start_with("Bearer")
  end

  it "recusa token errado" do
    mcp("tools/list", token: "outro")
    expect(response).to have_http_status(:unauthorized)
  end

  it "recusa o token de desenvolvimento para quem não é administrador" do
    comercial = create(:user, :comercial)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("MCP_DEV_USER").and_return(comercial.email)
    mcp("tools/list")
    expect(response).to have_http_status(:unauthorized)
  end

  it "lista as tools, marcando as de leitura" do
    mcp("tools/list")
    tool = tool_result["tools"].find { |t| t["name"] == "opcoes_comerciais" }
    expect(tool["annotations"]).to include("readOnlyHint" => true, "destructiveHint" => false)
  end

  it "devolve as opções do comercial como JSON" do
    service = create(:service, name: "Site institucional", default_price_cents: 450_000)
    mcp("tools/call", { name: "opcoes_comerciais", arguments: {} })
    expect(tool_result["isError"]).to be(false)
    data = JSON.parse(tool_result.dig("content", 0, "text"))
    expect(data["origens_lead"]).to include("outbound" => "Outbound")
    expect(data["servicos"]).to include(include("id" => service.id, "nome" => "Site institucional", "preco_padrao" => 4500.0))
    expect(data["usuarios"]).to include(include("id" => admin.id, "voce" => true))
  end

  it "marca na auditoria o que veio pelo MCP" do
    lead = create(:lead)
    mcp("tools/call", { name: "mover_lead", arguments: { id: lead.id, status: "contacted" } })
    expect(tool_result["isError"]).to be(false)
    expect(AuditLog.where(auditable: lead, action: "status_change").sole).to have_attributes(user: admin, ip_address: "mcp:127.0.0.1")
  end

  it "recusa argumento desconhecido com mensagem de erro, sem quebrar" do
    mcp("tools/call", { name: "buscar_leads", arguments: { cor: "azul" } })
    expect(tool_result["isError"]).to be(true)
  end

  it "aceita proximo_passo_em com data e hora ou só a data, e recusa outro formato pelo schema" do
    travel_to Time.zone.local(2026, 11, 11, 10)
    lead = create(:lead)
    mcp("tools/call", { name: "atualizar_lead", arguments: { id: lead.id, proximo_passo_em: "2026-11-12T08:15" } })
    expect(tool_result["isError"]).to be(false)
    mcp("tools/call", { name: "atualizar_lead", arguments: { id: lead.id, proximo_passo_em: "2026-11-13" } })
    expect(tool_result["isError"]).to be(false)
    expect(lead.reload.next_step_on).to eq(Time.zone.local(2026, 11, 13, 9))
    mcp("tools/call", { name: "atualizar_lead", arguments: { id: lead.id, proximo_passo_em: "13/11/2026" } })
    expect(tool_result["isError"]).to be(true)

    mcp("tools/call", { name: "proximos_passos", arguments: { de: "2026-11-13", incluir_atrasados: false } })
    expect(tool_result["isError"]).to be(false)
    expect(JSON.parse(tool_result.dig("content", 0, "text"))["proximos_passos"].pluck("id")).to eq([ lead.id ])
  end

  describe Mcp::Tools::Base do
    it "responde sem permissão quando o perfil não acessa a área" do
      response = call_tool(Mcp::Tools::OpcoesComerciais, create(:user, :desenvolvedor))
      expect(response).to be_error
      expect(response.content.dig(0, :text)).to eq("Sem permissão para esta ação.")
    end

    it "recusa usuário desativado" do
      expect(call_tool(Mcp::Tools::OpcoesComerciais, create(:user, :inactive))).to be_error
    end

    it "responde registro não encontrado para id inexistente ou inválido" do
      expect(call_tool(Mcp::Tools::VerLead, admin, id: SecureRandom.uuid).content.dig(0, :text)).to eq("Registro não encontrado.")
      expect(call_tool(Mcp::Tools::VerLead, admin, id: "abc")).to be_error
    end

    it "roda como o usuário do token" do
      seen = nil
      allow_any_instance_of(Mcp::Tools::OpcoesComerciais).to receive(:execute) { seen = Current.user; {} }
      call_tool(Mcp::Tools::OpcoesComerciais, admin)
      expect(seen).to eq(admin)
    end
  end
end
