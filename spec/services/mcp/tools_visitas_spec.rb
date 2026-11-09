require "rails_helper"

RSpec.describe "Tools das visitas do site no MCP" do
  let(:admin) { create(:user, :admin) }
  let(:comercial) { create(:user, :comercial) }
  let(:now) { Time.zone.local(2026, 11, 9, 14, 0) }

  around { |example| travel_to(now) { example.run } }

  before do
    create_site_visit(at: now - 1.hour, channel: "search", referrer: "google.com", pages: %w[/ /solucoes], duration: 90)
    create_site_visit(at: now - 2.hours, channel: "ai_assistant", referrer: "chatgpt.com", ai_assistant: "ChatGPT", pages: %w[/solucoes])
    create_site_visit(at: now - 8.days, channel: "search", referrer: "google.com")
    create_ai_hit(at: now - 1.hour)
    create_ai_hit(at: now - 1.hour, agent: "gptbot", name: "GPTBot", kind: "training", blocked: true)
  end

  def error_text(tool, user, **args)
    response = call_tool(tool, user, **args)
    expect(response).to be_error
    response.content.dig(0, :text)
  end

  it "as três estão registradas no endpoint e citadas nas instruções" do
    expect(Mcp::Endpoint::TOOLS).to include(Mcp::Tools::VisitasResumo, Mcp::Tools::VisitasPorDimensao, Mcp::Tools::AcessosIa)
    expect(Mcp::Endpoint::INSTRUCTIONS).to include("visitas_resumo", "visitas_por_dimensao", "acessos_ia")
  end

  describe Mcp::Tools::VisitasResumo do
    it "devolve os mesmos números da tela, com o período anterior e o link" do
      data = tool_data(described_class, admin, periodo: "7d")
      expected = JSON.parse(SiteVisits::Stats.new(SiteVisits::Stats.period("7d")).summary.to_json)

      expect(data.except("link")).to eq(expected)
      expect(data["indicadores"]).to include("visitantes" => 2, "visitas" => 2, "paginas_vistas" => 3)
      expect(data["anterior"]).to include("visitas" => 1)
      expect(data["link"]).to end_with("/marketing/site-visits?periodo=7d")
    end

    it "aceita filtros e intervalo livre" do
      expect(tool_data(described_class, admin, canal: "ai_assistant")["indicadores"]["visitas"]).to eq(1)
      data = tool_data(described_class, admin, de: "2026-10-30", ate: "2026-11-09")
      expect(data["periodo"]).to include("chave" => "personalizado", "de" => "2026-10-30", "ate" => "2026-11-09")
      expect(data["indicadores"]["visitas"]).to eq(3)
    end

    it "explica o erro de período ou de filtro para o Claude corrigir" do
      expect(error_text(described_class, admin, periodo: "semana")).to start_with("periodo desconhecido")
      expect(error_text(described_class, admin, de: "2024-01-01", ate: "2026-01-01")).to eq("Intervalo de até 400 dias.")
      expect(error_text(described_class, admin, canal: "tv")).to start_with("canal desconhecido")
    end

    it "recusa quem não tem a área de marketing" do
      expect(error_text(described_class, comercial)).to eq("Sem permissão para esta ação.")
    end
  end

  describe Mcp::Tools::VisitasPorDimensao do
    it "agrupa pela dimensão pedida, com limite" do
      data = tool_data(described_class, admin, dimensao: "pagina", limite: 1)
      expect(data["linhas"]).to eq([ { "valor" => "/solucoes", "rotulo" => "/solucoes", "visitantes" => 2, "visitas" => 2, "paginas_vistas" => 2,
                                       "percentual" => 100.0, "taxa_rejeicao" => 0.0, "duracao_media" => 53 } ])
      expect(data["outros"]).to eq("grupos" => 1, "visitas" => 1, "paginas_vistas" => 1)
      expect(tool_data(described_class, admin, dimensao: "origem", canal: "search")["linhas"].map { |l| l["rotulo"] }).to eq([ "google.com" ])
    end

    it "recusa dimensão desconhecida e quem não tem a área" do
      expect(error_text(described_class, admin, dimensao: "cidade")).to start_with("dimensao desconhecida")
      expect(error_text(described_class, comercial, dimensao: "canal")).to eq("Sem permissão para esta ação.")
    end
  end

  describe Mcp::Tools::AcessosIa do
    it "conta os acessos de IA servidos e bloqueados e compara com as visitas vindas de assistentes" do
      data = tool_data(described_class, admin)
      expect(data).to include("total" => 2, "servidos" => 1, "bloqueados" => 1, "falsos" => 0)
      expect(data["grupos"]).to eq([ { "valor" => "OpenAI", "rotulo" => "OpenAI", "acessos" => 2, "servidos" => 1, "bloqueados" => 1 } ])
      expect(data["visitas_de_assistentes_de_ia"]).to eq("visitas" => 1, "por_assistente" => { "ChatGPT" => 1 })
      expect(tool_data(described_class, admin, agrupar: "tipo", tipo: "training")["grupos"].map { |g| g["rotulo"] }).to eq([ "Treino" ])
    end

    it "recusa agrupamento ou tipo desconhecido e quem não tem a área" do
      expect(error_text(described_class, admin, agrupar: "pais")).to start_with("agrupar desconhecido")
      expect(error_text(described_class, admin, tipo: "robo")).to start_with("tipo desconhecido")
      expect(error_text(described_class, comercial)).to eq("Sem permissão para esta ação.")
    end
  end
end
