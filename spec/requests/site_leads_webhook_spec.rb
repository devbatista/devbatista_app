require "rails_helper"

RSpec.describe "Webhook de leads do site" do
  let!(:admin) { create(:user, name: "Rafael Batista") }

  let(:diagnosis) do
    { source: "diagnosis", site_id: "a1b2c3d4e5f60718", name: "Ana Souza", company: "Clínica Sorriso", email: "Ana@Clinica.com.br",
      phone: "11987654321", tier: "quente", summary: "Diagnóstico: Alto potencial de otimização (22 pontos) · potencial quente",
      details: "Diagnóstico Tecnológico — 29/10/2026 10:00\nPrincipal desafio: Automatização de tarefas" }
  end

  def post_lead(payload, token = "token-do-site-de-teste")
    post "/webhooks/site-leads", params: JSON.generate(payload),
                                 headers: { "Content-Type" => "application/json", "Authorization" => ("Bearer #{token}" if token) }.compact
  end

  it "cria o lead do diagnóstico, sem login, com a interação e o aviso ao responsável" do
    expect { post_lead(diagnosis) }.to change(Lead, :count).by(1).and change(Interaction, :count).by(1)
    expect(response).to have_http_status(:created)

    lead = Lead.find(response.parsed_body["id"])
    expect(lead).to have_attributes(name: "Ana Souza", company_name: "Clínica Sorriso", email: "ana@clinica.com.br", whatsapp: "(11) 98765-4321",
                                    origin: "diagnosis", status: "new", user: admin, external_id: "a1b2c3d4e5f60718", notes: diagnosis[:details])
    expect(lead.interactions.sole).to have_attributes(kind: "note", notes: diagnosis[:summary], user: admin, occurred_on: Date.current)
    expect(admin.notifications.sole).to have_attributes(kind: "site_lead", level: "warn", path: "/commercial/leads/#{lead.id}",
                                                        title: "Novo lead do site: Clínica Sorriso · Ana Souza · potencial quente")
  end

  it "cria o lead do e-book com o e-mail de nome provisório, sem aviso, e o diagnóstico depois completa o mesmo lead" do
    post_lead(source: "ebook", site_id: "e0e0e0e0e0e0e0e0", email: "ana@clinica.com.br", summary: "Baixou o e-book pelo site")
    expect(response).to have_http_status(:created)
    lead = Lead.sole
    expect(lead).to have_attributes(name: "ana@clinica.com.br", origin: "site", company_name: nil, notes: nil)
    expect(Notification.count).to eq(0)

    expect { post_lead(diagnosis) }.not_to change(Lead, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("id" => lead.id, "created" => false)
    expect(lead.reload).to have_attributes(name: "Ana Souza", company_name: "Clínica Sorriso", whatsapp: "(11) 98765-4321", origin: "site", notes: diagnosis[:details])
    expect(lead.interactions.pluck(:notes)).to contain_exactly("Baixou o e-book pelo site", diagnosis[:summary])
    expect(admin.notifications.sole.title).to eq("Clínica Sorriso · Ana Souza fez o Diagnóstico Tecnológico no site · potencial quente")
  end

  it "não desfaz o que foi editado à mão e soma o diagnóstico novo às observações" do
    lead = create(:lead, name: "Ana S.", company_name: "Sorriso Odonto", email: "ana@clinica.com.br", whatsapp: "(11) 90000-0000", notes: "Indicada pelo Paulo", user: admin)

    post_lead(diagnosis)
    expect(response).to have_http_status(:ok)
    expect(lead.reload).to have_attributes(name: "Ana S.", company_name: "Sorriso Odonto", whatsapp: "(11) 90000-0000",
                                           notes: "Indicada pelo Paulo\n\n#{diagnosis[:details]}")
  end

  it "abre lead novo quando o do mesmo e-mail já foi perdido ou convertido" do
    create(:lead, email: "ana@clinica.com.br", status: "lost", lost_reason: "Preço", user: admin)
    expect { post_lead(diagnosis) }.to change(Lead, :count).by(1)
    expect(response).to have_http_status(:created)
  end

  it "recusa token errado, ausente ou não configurado" do
    [ "outro-token", nil ].each do |token|
      expect { post_lead(diagnosis, token) }.not_to change(Lead, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    allow(Rails.configuration.x.site_leads).to receive(:token).and_return(nil)
    allow(Rails.logger).to receive(:error)
    post_lead(diagnosis, "")
    expect(response).to have_http_status(:unauthorized)
    expect(Rails.logger).to have_received(:error).with(/SITE_LEADS_TOKEN/)
  end

  it "devolve 422 com dados inválidos ou sem administrador para receber" do
    # Lead vazio é o teste de conexão do site (/api/health.php?check=crm): 422 prova que o token passou.
    post_lead([])
    expect(response).to have_http_status(:unprocessable_entity)
    post_lead(diagnosis.merge(email: "sem-arroba"))
    expect(response).to have_http_status(:unprocessable_entity)
    post_lead(diagnosis.merge(source: "outro"))
    expect(response).to have_http_status(:unprocessable_entity)
    post_lead(diagnosis.except(:name))
    expect(response).to have_http_status(:unprocessable_entity)

    admin.update!(active: false)
    post_lead(diagnosis)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to include("Nenhum administrador ativo para receber o lead")
    expect(Lead.count).to eq(0)
  end
end
