require "rails_helper"

RSpec.describe "Tools de próximos passos do MCP" do
  let(:now) { Time.zone.local(2026, 11, 11, 10) } # quarta-feira
  let(:admin) { create(:user) }
  let(:leitor) { create(:user, :financeiro) } # comercial só leitura

  around { |example| travel_to(now) { example.run } }

  def error_text(tool, user, **args)
    response = call_tool(tool, user, **args)
    expect(response).to be_error
    response.content.dig(0, :text)
  end

  describe Mcp::Tools::ProximosPassos do
    let!(:late) { create(:lead, name: "Ana", next_step: "Ligar", next_step_on: now - 1.day, whatsapp: "11 98888-7777") }
    let!(:today) { create(:opportunity, title: "Portal", next_step: "Reunião", next_step_on: now + 4.hours) }
    let!(:next_week) { create(:lead, name: "Caio", next_step: "Follow-up", next_step_on: now + 6.days) }
    let!(:undated) { create(:lead, name: "Eva") }

    it "lista pela data e hora, com o formato pedido e a última interação" do
      create(:interaction, subject: late, notes: "Mandei o orçamento por e-mail", kind: "email", occurred_on: now.to_date - 2)
      data = tool_data(described_class, leitor)
      expect(data).to include("agora" => "2026-11-11T10:00:00-03:00", "total" => 3, "mostrando" => 3)
      expect(data["proximos_passos"].pluck("nome")).to eq(%w[Ana Portal Caio])

      first = data["proximos_passos"].first
      expect(first).to include("tipo" => "lead", "id" => late.id, "empresa" => "Empresa do lead", "acao" => "Ligar",
                               "quando" => "2026-11-10T10:00:00-03:00", "atrasado" => true, "grupo" => "atrasados",
                               "status" => "new", "status_rotulo" => "Novo Lead", "whatsapp" => "11 98888-7777",
                               "link" => end_with("/commercial/leads/#{late.id}"))
      expect(first["ultima_interacao"]).to eq("data" => "2026-11-09", "tipo" => "email", "texto" => "Mandei o orçamento por e-mail")
      expect(data["proximos_passos"].second).to include("tipo" => "oportunidade", "atrasado" => false, "ultima_interacao" => nil,
                                                        "link" => end_with("/commercial/opportunities/#{today.id}/edit"))
    end

    it "filtra pelo período, com os atrasados e os sem data como opções" do
      names = ->(**args) { tool_data(described_class, admin, **args)["proximos_passos"].pluck("nome") }
      expect(names.call(de: "2026-11-11", ate: "2026-11-11")).to eq(%w[Ana Portal])
      expect(names.call(de: "2026-11-11", ate: "2026-11-11", incluir_atrasados: false)).to eq(%w[Portal])
      expect(names.call(de: "2026-11-11T15:00", incluir_atrasados: false)).to eq(%w[Caio])
      expect(names.call(incluir_sem_data: true)).to eq(%w[Ana Portal Caio Eva])
      expect(names.call(tipo: "oportunidade")).to eq(%w[Portal])
      expect(names.call(limite: 2)).to eq(%w[Ana Portal])
    end

    it "recusa data inválida e período invertido" do
      expect(error_text(described_class, admin, de: "ontem")).to include("Data inválida")
      expect(error_text(described_class, admin, de: "2026-11-12", ate: "2026-11-11")).to include("depois de `ate`")
    end
  end

  describe Mcp::Tools::ConcluirPasso do
    let(:lead) { create(:lead, next_step: "Ligar", next_step_on: now - 1.hour) }

    it "grava a interação e o novo próximo passo" do
      data = tool_data(described_class, admin, tipo: "lead", id: lead.id, o_que_foi_feito: "Liguei, pediu proposta",
                                               tipo_interacao: "call", proximo_passo: "Enviar proposta", proximo_passo_em: "2026-11-12T15:30")
      expect(data["interacao"]).to include("tipo" => "call", "notas" => "Liguei, pediu proposta", "data" => "2026-11-11")
      expect(data["lead"]).to include("proximo_passo" => "Enviar proposta", "proximo_passo_em" => "2026-11-12T15:30:00-03:00")
      expect(lead.reload.next_step_on).to eq(Time.zone.local(2026, 11, 12, 15, 30))
      expect(AuditLog.where(auditable: lead, user: admin)).to exist
    end

    it "marca a oportunidade como perdida" do
      opportunity = create(:opportunity, next_step_on: now)
      data = tool_data(described_class, admin, tipo: "oportunidade", id: opportunity.id, o_que_foi_feito: "Fechou com outro",
                                               tipo_interacao: "whatsapp", marcar_perdido: true, motivo: "Optou por concorrente")
      expect(data["oportunidade"]).to include("etapa" => "lost", "motivo_perda" => "Optou por concorrente")
      expect(opportunity.interactions.sole.kind).to eq("whatsapp")
    end

    it "não conclui sem próximo passo nem perdido, nem com os dois" do
      base = { tipo: "lead", id: lead.id, o_que_foi_feito: "Liguei", tipo_interacao: "call" }
      expect(error_text(described_class, admin, **base)).to include("Defina o próximo passo")
      expect(error_text(described_class, admin, **base, proximo_passo: "Enviar proposta")).to include("Data e hora do próximo passo não pode ficar em branco")
      expect(error_text(described_class, admin, **base, marcar_perdido: true)).to include("Motivo da perda não pode ficar em branco")
      expect(error_text(described_class, admin, **base, marcar_perdido: true, motivo: "Preço", proximo_passo: "X")).to include("não os dois")
      expect(error_text(described_class, admin, **base, proximo_passo: "X", proximo_passo_em: "logo")).to include("proximo_passo_em inválido")
      expect(lead.reload).to have_attributes(next_step: "Ligar", status: "new")
      expect(Interaction.count).to eq(0)
    end

    it "respeita a permissão" do
      expect(error_text(described_class, leitor, tipo: "lead", id: lead.id, o_que_foi_feito: "x", tipo_interacao: "call",
                                                 marcar_perdido: true, motivo: "Preço")).to eq("Sem permissão para esta ação.")
    end
  end

  describe "proximo_passo_em nas tools de criar e atualizar" do
    it "aceita data e hora no atualizar_lead e só a data (09:00) no criar_leads" do
      lead = create(:lead)
      data = tool_data(Mcp::Tools::AtualizarLead, admin, id: lead.id, proximo_passo_em: "2026-11-12T08:15")
      expect(data["proximo_passo_em"]).to eq("2026-11-12T08:15:00-03:00")

      data = tool_data(Mcp::Tools::CriarLeads, admin, leads: [ { nome: "Novo", origem: "site", proximo_passo: "Ligar", proximo_passo_em: "2026-11-20" } ])
      expect(Lead.find_by!(name: "Novo").next_step_on).to eq(Time.zone.local(2026, 11, 20, 9))
      expect(data["leads"].first["proximo_passo_em"]).to eq("2026-11-20T09:00:00-03:00")
    end

    it "aceita data e hora no criar_oportunidade e no atualizar_oportunidade, e recusa texto inválido" do
      company = create(:company)
      data = tool_data(Mcp::Tools::CriarOportunidade, admin, titulo: "Portal", empresa_id: company.id, valor_estimado: 1000,
                                                             proximo_passo: "Reunião", proximo_passo_em: "2026-11-13T11:00")
      opportunity = Opportunity.find(data["id"])
      expect(opportunity.next_step_on).to eq(Time.zone.local(2026, 11, 13, 11))

      tool_data(Mcp::Tools::AtualizarOportunidade, admin, id: opportunity.id, proximo_passo_em: "2026-11-14")
      expect(opportunity.reload.next_step_on).to eq(Time.zone.local(2026, 11, 14, 9))

      expect(error_text(Mcp::Tools::AtualizarOportunidade, admin, id: opportunity.id, proximo_passo_em: "semana que vem"))
        .to include("proximo_passo_em inválido")
      tool_data(Mcp::Tools::AtualizarOportunidade, admin, id: opportunity.id, proximo_passo_em: nil)
      expect(opportunity.reload.next_step_on).to be_nil
    end
  end

  it "orienta o Claude a começar por proximos_passos e concluir com concluir_passo" do
    expect(Mcp::Endpoint::INSTRUCTIONS).to include("No começo de uma sessão comercial, chame proximos_passos; ao concluir uma ação, use concluir_passo")
    expect(Mcp::Endpoint::TOOLS).to include(Mcp::Tools::ProximosPassos, Mcp::Tools::ConcluirPasso)
  end
end
