require "rails_helper"

RSpec.describe "Operação" do
  let(:admin) { create(:user, :admin) }
  let(:dev) { create(:user, :desenvolvedor, name: "Diego Rocha") }
  let(:company) { create(:company, trade_name: "Empresa ACME") }

  describe "Projetos" do
    it "lista com destaque para o atrasado e abre o projeto" do
      late = create(:project, company: company, name: "ERP Cliente C", start_date: Date.current - 90, due_date: Date.current - 7)
      create(:project, company: company, name: "Portal ACME — Fase 2")
      sign_in dev
      get projects_path
      expect(response.body).to include("ERP Cliente C", "Portal ACME — Fase 2", "7 dias de atraso", "Atrasado")
      get projects_path(atrasados: "1")
      expect(response.body).not_to include("Portal ACME — Fase 2")
      get project_path(late)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Orçamento × horas registradas", "Tarefas por status")
    end

    it "cadastra o projeto" do
      sign_in dev
      post projects_path, params: { project: { company_id: company.id, name: "App Orion", user_id: dev.id, status: "planning",
                                               start_date: Date.current, due_date: Date.current + 60, budget: "22.000,00", progress_from_tasks: "1" } }
      project = Project.find_by!(name: "App Orion")
      expect(response).to redirect_to(project_path(project))
      expect(project.budget_cents).to eq(2_200_000)
    end

    it "deixa o comercial consultar, mas não cadastrar, e barra o financeiro" do
      sign_in create(:user, :comercial)
      get projects_path
      expect(response).to have_http_status(:ok)
      post projects_path, params: { project: { name: "X" } }
      expect(response).to have_http_status(:forbidden)
      sign_in create(:user, :financeiro)
      get projects_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Tarefas" do
    let(:project) { create(:project, company: company) }

    it "mostra o quadro e a lista com estimativa × horas registradas" do
      task = create(:task, project: project, title: "Módulo de relatórios", status: "in_progress", estimated_hours: "24")
      create(:time_entry, company: company, project: project, task: task, minutes: 18 * 60)
      sign_in dev
      get tasks_path
      expect(response.body).to include("Módulo de relatórios", "Em revisão", "18h / 24h")
      get tasks_path(modo: "lista")
      expect(response.body).to include("Registradas × estimativa", "18h / 24h")
    end

    it "muda o status ao arrastar e recalcula o progresso do projeto" do
      task = create(:task, project: project)
      create(:task, project: project)
      sign_in dev
      patch move_task_path(task, to: "done", format: :json)
      expect(response.parsed_body["ok"]).to be(true)
      expect(task.reload).to be_done
      expect(project.reload.progress).to eq(50)
    end

    it "deixa o suporte ver o quadro, mas não mexer" do
      task = create(:task, project: project)
      sign_in create(:user, :suporte)
      get tasks_path
      expect(response).to have_http_status(:ok)
      patch move_task_path(task, to: "done", format: :json)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Horas trabalhadas" do
    it "registra sempre em nome de quem lança quando o perfil é Próprio" do
      sign_in dev
      post time_entries_path, params: { time_entry: { company_id: company.id, worked_on: Date.current, duration: "02:30", user_id: admin.id } }
      entry = TimeEntry.last
      expect(entry.user).to eq(dev)
      expect(entry.minutes).to eq(150)
    end

    it "mostra e deixa editar só os próprios lançamentos no perfil Próprio" do
      mine = create(:time_entry, user: dev, company: company, description: "Meu lançamento")
      other = create(:time_entry, user: admin, company: company, description: "Lançamento do admin")
      sign_in dev
      get time_entries_path
      expect(response.body).to include("Meu lançamento")
      expect(response.body).not_to include("Lançamento do admin")
      patch time_entry_path(other), params: { time_entry: { duration: "1:00" } }
      expect(response).to have_http_status(:forbidden)
      patch time_entry_path(mine), params: { time_entry: { duration: "1:00" } }
      expect(mine.reload.minutes).to eq(60)
    end

    it "deixa o administrador lançar para outra pessoa" do
      sign_in admin
      post time_entries_path, params: { time_entry: { company_id: company.id, worked_on: Date.current, duration: "1h", user_id: dev.id } }
      expect(TimeEntry.last.user).to eq(dev)
    end

    it "volta com erro sem cliente ou duração" do
      sign_in dev
      post time_entries_path, params: { time_entry: { worked_on: Date.current, duration: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Cliente é obrigatório", "Duração precisa ser informada")
    end

    it "deixa o financeiro consultar, mas não lançar" do
      sign_in create(:user, :financeiro)
      get time_entries_path
      expect(response).to have_http_status(:ok)
      post time_entries_path, params: { time_entry: { company_id: company.id, worked_on: Date.current, duration: "1:00" } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Chamados" do
    let(:suporte) { create(:user, :suporte, name: "Carla Mendes") }

    it "abre o chamado com número, contato principal e alerta imediato se crítico" do
      contact = create(:contact, company: company, primary: true)
      sign_in suporte
      post tickets_path, params: { ticket: { company_id: company.id, subject: "Sistema fora do ar", description: "API com erro 502",
                                             category: "infrastructure", priority: "critical", user_id: suporte.id } }
      ticket = Ticket.last
      expect(response).to redirect_to(ticket_path(ticket))
      expect(ticket.contact).to eq(contact)
      expect(Notification.where(kind: "ticket_critical", user: suporte)).to exist
      follow_redirect!
      expect(response.body).to include("Sistema fora do ar", "API com erro 502", "Histórico do atendimento")
    end

    it "registra resposta, nota interna e muda o status ao enviar" do
      ticket = create(:ticket, company: company)
      sign_in suporte
      post ticket_messages_path(ticket), params: { ticket_message: { kind: "note", body: "Disco cheio no servidor" }, status_after: "in_progress" }
      expect(ticket.reload).to be_status_in_progress
      expect(ticket.messages.last).to be_note
      get ticket_path(ticket)
      expect(response.body).to include("Disco cheio no servidor", "Nota interna")
    end

    it "registra a conclusão ao resolver" do
      ticket = create(:ticket, company: company)
      sign_in suporte
      patch status_ticket_path(ticket), params: { status_change: { status: "resolved", message: "Rotação de logs configurada" } }
      expect(ticket.reload).to be_status_resolved
      expect(ticket.resolved_at).to be_present
      expect(ticket.messages.last.body).to eq("Rotação de logs configurada")
    end

    it "deixa o comercial consultar, mas não abrir chamado, e barra o financeiro" do
      ticket = create(:ticket, company: company)
      sign_in create(:user, :comercial)
      get ticket_path(ticket)
      expect(response).to have_http_status(:ok)
      post tickets_path, params: { ticket: { subject: "X" } }
      expect(response).to have_http_status(:forbidden)
      sign_in create(:user, :financeiro)
      get tickets_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Visão 360º, busca e documentos" do
    it "mostra as abas e os cartões de projetos e chamados" do
      create(:project, company: company, name: "Portal ACME — Fase 2")
      create(:ticket, company: company, subject: "Lentidão na listagem", priority: "high")
      sign_in admin
      get company_path(company)
      expect(response.body).to include('data-tab="projetos"', 'data-tab="chamados"', "Portal ACME — Fase 2", "Lentidão na listagem", "nenhum crítico")
    end

    it "esconde as abas para quem não tem acesso" do
      sign_in create(:user, :financeiro)
      get company_path(company)
      expect(response.body).not_to include('data-tab="projetos"', 'data-tab="chamados"')
    end

    it "encontra projeto e chamado pelo nome e pelo número" do
      create(:project, company: company, name: "Painel de indicadores")
      ticket = create(:ticket, company: company, subject: "Usuário sem acesso")
      sign_in admin
      get search_path(q: "Painel", format: :json)
      expect(response.parsed_body.map { |g| g["label"] }).to include("Projetos")
      get search_path(q: "##{ticket.number}", format: :json)
      expect(response.parsed_body.flat_map { |g| g["items"].map { |i| i["title"] } }).to include("#{ticket.code} — Usuário sem acesso")
    end

    it "anexa documento ao projeto" do
      project = create(:project, company: company)
      sign_in admin
      post documents_path, params: { document: { kind: "technical", documentable_type: "Project", documentable_id: project.id,
                                                 file: Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", original_filename: "escopo.pdf") } }
      expect(response).to redirect_to(project_path(project, aba: "documentos"))
      expect(project.documents.last.company).to eq(company)
    end
  end
end
