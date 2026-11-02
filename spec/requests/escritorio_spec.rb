require "rails_helper"

RSpec.describe "Agentes IA → Escritório e Eventos" do
  let(:admin) { create(:user, :admin) }
  let(:leitor) { create(:user, role: create(:role, permissions: { "agentes" => "read" })) }
  let(:frame) { { "Turbo-Frame" => "agent_panel" } }
  let(:stream) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  before { Agent.seed_defaults! }

  def agent(key) = Agent.find_by!(key: key)

  describe "escritório" do
    before { sign_in admin }

    it "mostra uma sala por agente e abre o primeiro com aprovação pendente" do
      create(:agent_event, agent: agent("ops"), title: "Checando backups")
      create(:agent_event, :approval, agent: agent("leo"), title: "Subir a verba", summary: "CPL abaixo da meta.")

      get escritorio_path

      body = response.body
      expect(body.scan('id="desk_agent_').size).to eq(5)
      expect(body).to include(%(id="#{ActionView::RecordIdentifier.dom_id(agent('leo'), :desk)}" class="desk on" aria-current="true"))
      expect(body).to include("Sala · Infra", "Checando backups", "Trabalhando", "1 aprovação", %(data-agent-status="awaiting_approval"))
      expect(body).to include(%(data-escritorio-selected-value="leo"), "Painel de Leo", "Aguardando sua aprovação", "Subir a verba", "CPL abaixo da meta.",
                              "Aprovar", "Rejeitar", "Deixar uma ordem")
      expect(body).to include(%(<turbo-cable-stream-source channel="EscritorioStreamsChannel"))
    end

    it "abre o agente da URL" do
      get escritorio_path(agente: "fin")
      expect(response.body).to include("Painel de Fin", "Nenhum evento ainda")
    end

    it "menu com o grupo Agentes IA, Rotinas em breve" do
      get escritorio_path
      menu = response.body[/<aside class="side".*?<\/aside>/m]
      expect(menu).to include("Agentes IA", %(href="#{escritorio_path}"), %(href="#{agent_events_path}"))
      expect(menu).to match(/Rotinas<small>em breve<\/small>/)
    end

    it "sem agentes ativos, explica" do
      Agent.update_all(active: false)
      get escritorio_path
      expect(response.body).to include("Nenhum agente ativo")
    end
  end

  describe "painel" do
    before { sign_in admin }

    it "no frame, devolve o painel com as ordens e a linha do tempo de hoje" do
      sol = agent("sol")
      create(:agent_event, agent: sol, title: "Ontem", created_at: 1.day.ago)
      create(:agent_event, agent: sol, title: "Qualificando leads", payload: { leads: [ "<b>Padaria</b>" ] })
      create(:agent_order, agent: sol, user: admin, body: "Priorize o e-book", delivered_at: 1.minute.ago)

      get agent_path(sol), headers: frame

      body = response.body
      expect(body).to start_with(%(<turbo-frame id="agent_panel"))
      expect(body).to include("Qualificando leads", "Priorize o e-book", "Sol já leu", "&lt;b&gt;Padaria&lt;/b&gt;")
      expect(body).not_to include("<b>Padaria</b>", ">Ontem<")
    end

    it "fora do frame, leva ao escritório com o agente aberto" do
      get agent_path(agent("sol"))
      expect(response).to redirect_to(escritorio_path(agente: "sol"))
    end

    it "as partes ao vivo, que o tempo real recarrega" do
      sol = agent("sol")
      get live_agent_path(sol)
      expect(response.body).to start_with(%(<turbo-frame id="#{ActionView::RecordIdentifier.dom_id(sol, :panel)}"))
      get log_agent_path(sol)
      expect(response.body).to start_with(%(<turbo-frame id="#{ActionView::RecordIdentifier.dom_id(sol, :log)}"))
    end
  end

  describe "decisão" do
    let!(:event) { create(:agent_event, :approval, agent: agent("sol"), title: "Enviar follow-up") }

    it "aprova com observação e redesenha o painel" do
      sign_in admin
      post agent_event_decision_path(event), params: { decisao: "approved", observacao: "Pode mandar" }, headers: stream
      expect(response).to have_http_status(:ok)
      expect(event.reload).to have_attributes(decision: "approved", decided_by: admin, decision_note: "Pode mandar")
      expect(response.body).to include(%(target="#{ActionView::RecordIdentifier.dom_id(event.agent, :panel)}"), "Aprovado por")
      expect(response.body).not_to include("Aguardando sua aprovação")
    end

    it "não decide duas vezes" do
      sign_in admin
      event.decide!("rejected", by: admin)
      post agent_event_decision_path(event), params: { decisao: "approved" }, headers: stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("já foi registrada")
      expect(event.reload.decision).to eq("rejected")
    end

    it "sem Turbo, volta ao escritório com o aviso" do
      sign_in admin
      post agent_event_decision_path(event), params: { decisao: "rejected" }
      expect(response).to redirect_to(escritorio_path(agente: "sol"))
      expect(flash[:notice]).to eq("Rejeitado · Enviar follow-up")
    end

    it "quem só lê não vê os botões e recebe 403" do
      sign_in leitor
      get live_agent_path(event.agent)
      expect(response.body).to include("Enviar follow-up")
      expect(response.body).not_to include("Aprovar")
      post agent_event_decision_path(event), params: { decisao: "approved" }
      expect(response).to have_http_status(:forbidden)
      expect(event.reload).to be_decision_pending
    end
  end

  describe "ordem" do
    it "deixa a ordem em nome de quem está logado e limpa o campo" do
      sign_in admin
      post agent_agent_orders_path(agent("sol")), params: { agent_order: { body: "Priorize o e-book" } }, headers: stream
      order = AgentOrder.sole
      expect(order).to have_attributes(agent: agent("sol"), user: admin, body: "Priorize o e-book", status: "pending")
      expect(response.body).to include(%(target="#{ActionView::RecordIdentifier.dom_id(order.agent, :order_form)}"), "Priorize o e-book", "ainda não lida")
    end

    it "recusa ordem vazia" do
      sign_in admin
      post agent_agent_orders_path(agent("sol")), params: { agent_order: { body: " " } }, headers: stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(AgentOrder.count).to eq(0)
    end

    it "quem só lê não deixa ordem nem vê o campo" do
      sign_in leitor
      get escritorio_path
      expect(response.body).not_to include("Deixar uma ordem")
      post agent_agent_orders_path(agent("sol")), params: { agent_order: { body: "x" } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "eventos" do
    before { sign_in admin }

    it "lista com filtros de agente, status, aprovação e período" do
      create(:agent_event, agent: agent("ops"), title: "Backups conferidos", status: "done")
      create(:agent_event, :approval, agent: agent("sol"), title: "Enviar follow-up")
      create(:agent_event, agent: agent("fin"), title: "Conciliação antiga", status: "error", created_at: 10.days.ago)

      get agent_events_path
      expect(response.body).to include("Backups conferidos", "Enviar follow-up", "Conciliação antiga", "Pendente")

      get agent_events_path(agente: "ops")
      expect(response.body).to include("Backups conferidos").and(exclude("Enviar follow-up"))

      get agent_events_path(aprovacao: "pending")
      expect(response.body).to include("Enviar follow-up").and(exclude("Backups conferidos"))

      get agent_events_path(status: "error")
      expect(response.body).to include("Conciliação antiga").and(exclude("Enviar follow-up"))

      get agent_events_path(periodo: "7d")
      expect(response.body).not_to include("Conciliação antiga")
    end
  end

  it "perfil sem a área recebe 403 em todas as telas" do
    sign_in create(:user, :comercial)
    event = create(:agent_event, :approval, agent: agent("sol"))
    [ escritorio_path, agent_events_path, agent_path(agent("sol")), live_agent_path(agent("sol")), log_agent_path(agent("sol")) ].each do |path|
      get path
      expect(response).to have_http_status(:forbidden), path
    end
    post agent_event_decision_path(event), params: { decisao: "approved" }
    expect(response).to have_http_status(:forbidden)
    post agent_agent_orders_path(agent("sol")), params: { agent_order: { body: "x" } }
    expect(response).to have_http_status(:forbidden)

    get root_path
    expect(response.body[/<aside class="side".*?<\/aside>/m]).not_to include("Agentes IA")
  end
end
