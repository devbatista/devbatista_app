require "rails_helper"

RSpec.describe "Comercial" do
  let(:comercial) { create(:user, :comercial) }

  it "monta o pipeline com leads e oportunidades" do
    create(:lead, company_name: "Transportes Lima", status: "new")
    create(:opportunity, title: "Portal de Pedidos", stage: "proposal")
    sign_in comercial
    get pipeline_path
    expect(response.body).to include("Transportes Lima", "Portal de Pedidos", "Novo Lead", "Negociação")
  end

  it "move o lead entre as etapas de lead pelo quadro" do
    lead = create(:lead)
    sign_in comercial
    patch move_lead_path(lead, to: "contacted", format: :json)
    expect(response.parsed_body["ok"]).to be(true)
    expect(lead.reload).to be_status_contacted
  end

  it "não deixa o lead pular para etapa de oportunidade sem converter" do
    lead = create(:lead)
    sign_in comercial
    patch move_lead_path(lead, to: "meeting", format: :json)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "marca a oportunidade como perdida com motivo" do
    opp = create(:opportunity)
    sign_in comercial
    patch lose_opportunity_path(opp), params: { loss: { lost_reason: "Sem orçamento" } }
    expect(opp.reload).to be_stage_lost
  end

  it "converte o lead pela tela" do
    lead = create(:lead, status: "qualified")
    sign_in comercial
    post lead_conversion_path(lead), params: { conversion: { trade_name: "Nova Empresa", cnpj: "11.222.333/0001-81", contact_name: "Ana",
                                                             title: "Projeto", stage: "meeting", user_id: comercial.id, contact_primary: "1" } }
    company = Company.find_by!(trade_name: "Nova Empresa")
    expect(response).to redirect_to(company_path(company))
    expect(company.opportunities.count).to eq(1)
  end

  it "cria proposta com itens e calcula o total" do
    company = create(:company)
    service = create(:service, default_price_cents: 300_000)
    sign_in comercial
    post proposals_path, params: { proposal: { title: "Portal", company_id: company.id, user_id: comercial.id, valid_until: Date.current + 15,
                                               items_attributes: { "0" => { service_id: service.id, price: "2500", recurrence: "monthly" },
                                                                   "1" => { service_id: service.id, price: "1000", recurrence: "one_off" } } } }
    proposal = Proposal.last
    expect(response).to redirect_to(proposal_path(proposal))
    expect(proposal.total_cents).to eq(350_000)
  end

  it "envia, aprova e gera o contrato" do
    proposal = create(:proposal, company: create(:company))
    sign_in comercial
    patch mark_proposal_path(proposal, to: "sent")
    expect(proposal.reload).to be_sent
    post approve_proposal_path(proposal), params: { approval: { approved_on: Date.current, start_date: Date.current, end_date: Date.current + 1.year, due_day: 10, renewal: "manual" } }
    expect(proposal.reload).to be_approved
    expect(response).to redirect_to(contract_path(proposal.contract))
  end

  it "responde 403 para quem não acessa o Comercial" do
    sign_in create(:user, :suporte)
    get pipeline_path
    expect(response).to have_http_status(:forbidden)
  end

  it "deixa o financeiro consultar, mas não criar proposta" do
    sign_in create(:user, :financeiro)
    get proposals_path
    expect(response).to have_http_status(:ok)
    post proposals_path, params: { proposal: { title: "X" } }
    expect(response).to have_http_status(:forbidden)
  end
end
