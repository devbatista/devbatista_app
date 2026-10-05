require "rails_helper"

RSpec.describe "Operação" do
  describe Project do
    it "fica atrasado quando passa da previsão sem concluir ou cancelar" do
      late = create(:project, start_date: Date.current - 60, due_date: Date.current - 1)
      on_time = create(:project, due_date: Date.current)
      done = create(:project, start_date: Date.current - 60, due_date: Date.current - 5, status: "done")
      cancelled = create(:project, start_date: Date.current - 60, due_date: Date.current - 5, status: "cancelled")
      expect(late).to be_late
      expect([ on_time, done, cancelled ]).to all(satisfy { |p| !p.late? })
      expect(Project.late).to contain_exactly(late)
    end

    it "calcula o progresso pelas tarefas concluídas" do
      project = create(:project)
      tasks = create_list(:task, 4, project: project)
      tasks.first.update!(status: "done")
      expect(project.reload.progress).to eq(25)
      tasks.second.update!(status: "done")
      expect(project.reload.progress).to eq(50)
      tasks.first.destroy!
      expect(project.reload.progress).to eq(33)
    end

    it "mantém o progresso informado no modo manual" do
      project = create(:project, progress_from_tasks: false, progress: 81)
      create(:task, project: project, status: "done")
      expect(project.reload.progress).to eq(81)
    end

    it "guarda a data de conclusão e soma a estimativa das tarefas" do
      project = create(:project)
      create(:task, project: project, estimated_hours: "8")
      create(:task, project: project, estimated_hours: "1,5")
      expect(project.estimated_minutes).to eq(570)
      project.update!(status: "done")
      expect(project.closed_on).to eq(Date.current)
    end

    it "não aceita contrato de outra empresa" do
      project = build(:project, contract: create(:contract))
      expect(project).not_to be_valid
      expect(project.errors[:contract]).to be_present
    end

    it "grava auditoria e histórico na criação e na mudança de status" do
      project = create(:project)
      project.update!(status: "paused")
      expect(AuditLog.where(auditable: project).pluck(:action)).to eq(%w[create status_change])
      expect(Activity.where(subject: project).last.description).to eq("Mudou o status de o projeto #{project.name}: Em andamento → Pausado")
      expect(Activity.where(subject: project).last.company).to eq(project.company)
    end
  end

  describe Task do
    it "registra a conclusão e a apaga ao reabrir" do
      task = create(:task)
      task.update!(status: "done")
      expect(task.completed_on).to eq(Date.current)
      task.update!(status: "review")
      expect(task.completed_on).to be_nil
    end

    it "fica atrasada com prazo vencido e não concluída" do
      late = create(:task, due_on: Date.current - 2)
      create(:task, due_on: Date.current - 2, status: "done")
      create(:task, due_on: Date.current)
      expect(Task.late).to contain_exactly(late)
      expect(late.days_late).to eq(2)
    end

    it "compara a estimativa com as horas registradas" do
      task = create(:task, estimated_hours: "2")
      expect(task.over_estimate?(150)).to be(true)
      expect(task.over_estimate?(120)).to be(false)
    end
  end

  describe TimeEntry do
    it "exige cliente e duração; projeto e tarefa são opcionais" do
      entry = TimeEntry.new(user: create(:user), worked_on: Date.current)
      expect(entry).not_to be_valid
      expect(entry.errors.attribute_names).to include(:company, :minutes)
      entry.company = create(:company)
      entry.duration = "01:30"
      expect(entry).to be_valid
    end

    it "entende a duração em hh:mm, 1h30, minutos e horas decimais" do
      expect(%w[01:30 1:30 1h30 90min 1,5 1.5].map { |t| TimeEntry.parse_duration(t) }).to all(eq(90))
      expect(TimeEntry.parse_duration("2h")).to eq(120)
      expect(TimeEntry.parse_duration("abc")).to be_nil
      expect(build(:time_entry, minutes: 25 * 60)).not_to be_valid
    end

    it "completa projeto e cliente a partir da tarefa" do
      task = create(:task)
      entry = TimeEntry.create!(user: create(:user), task: task, worked_on: Date.current, duration: "2:00")
      expect([ entry.project, entry.company ]).to eq([ task.project, task.project.company ])
    end

    it "recusa projeto de outro cliente" do
      entry = build(:time_entry, project: create(:project))
      expect(entry).not_to be_valid
      expect(entry.errors[:project]).to be_present
    end

    it "escreve o histórico como lançamento de horas" do
      project = create(:project, name: "ERP Cliente C")
      user = create(:user, name: "Elisa Prado")
      Current.user = user
      create(:time_entry, user: user, company: project.company, project: project, minutes: 210)
      expect(Activity.last).to have_attributes(description: "Registrou 3h30 em ERP Cliente C", company: project.company)
    ensure
      Current.reset
    end
  end

  describe Ticket do
    it "numera em sequência e registra a abertura" do
      first = create(:ticket)
      second = create(:ticket)
      expect(second.number).to eq(first.number + 1)
      expect(first.code).to eq("##{first.number}")
      expect(first.opened_at).to be_within(5.seconds).of(Time.current)
      expect(first).to be_status_open
    end

    it "sugere o contato principal da empresa" do
      company = create(:company)
      contact = create(:contact, company: company, primary: true)
      expect(create(:ticket, company: company).contact).to eq(contact)
    end

    it "registra a conclusão ao resolver e apaga ao reabrir" do
      ticket = create(:ticket)
      ticket.update!(status: "resolved")
      expect(ticket.resolved_at).to be_within(5.seconds).of(Time.current)
      ticket.update!(status: "closed")
      expect(ticket.resolved_at).to be_present
      ticket.update!(status: "in_progress")
      expect(ticket.resolved_at).to be_nil
    end

    it "notifica suporte, desenvolvedor e administrador na hora quando é crítico" do
      suporte = create(:user, :suporte)
      dev = create(:user, :desenvolvedor)
      admin = create(:user, :admin)
      create(:user, :comercial)
      ticket = create(:ticket, priority: "critical")
      expect(Notification.where(kind: "ticket_critical").map(&:user)).to contain_exactly(suporte, dev, admin)
      expect(Notification.last).to have_attributes(notifiable: ticket, level: "crit")
      expect { ticket.update!(priority: "high") && ticket.update!(priority: "critical") }.not_to change(Notification, :count)
    end

    it "notifica quando a prioridade muda para Crítica" do
      create(:user, :suporte)
      ticket = create(:ticket, priority: "normal")
      expect { ticket.update!(priority: "critical") }.to change(Notification, :count).by(1)
      expect(Notification.last.title).to include("passou para prioridade Crítica")
    end
  end

  describe OperationAlertsJob do
    let(:today) { Date.new(2026, 9, 17) }

    it "avisa o responsável e os administradores do projeto atrasado, uma vez por dia" do
      owner = create(:user, :desenvolvedor)
      admin = create(:user, :admin)
      create(:user, :suporte)
      project = create(:project, user: owner, start_date: today - 60, due_date: today - 1)
      expect { 2.times { described_class.perform_now(today) } }.to change(Notification, :count).by(2)
      expect(Notification.where(notifiable: project).map(&:user)).to contain_exactly(owner, admin)
      expect(Notification.last.title).to eq("Projeto #{project.name} passou da previsão")
    end

    it "repete o aviso do projeto a cada 7 dias de atraso" do
      owner = create(:user, :desenvolvedor)
      project = create(:project, user: owner, start_date: today - 60, due_date: today - 1)
      described_class.perform_now(today)
      described_class.perform_now(today + 3)
      expect(Notification.where(notifiable: project, user: owner).count).to eq(1)
      described_class.perform_now(today + 6)
      expect(Notification.where(notifiable: project, user: owner).last.title).to eq("Projeto #{project.name} está atrasado há 7 dias")
    end

    it "avisa o responsável pela tarefa atrasada (ou o do projeto, se não houver)" do
      dev = create(:user, :desenvolvedor)
      owner = create(:user, :desenvolvedor)
      project = create(:project, user: owner, due_date: today + 30)
      with_user = create(:task, project: project, user: dev, title: "Fechamento de estoque", due_on: today - 6)
      without = create(:task, project: project, due_on: today - 1)
      create(:task, project: project, due_on: today - 1, status: "done")
      described_class.perform_now(today)
      expect(Notification.find_by(notifiable: with_user)).to have_attributes(user: dev, title: "Tarefa “Fechamento de estoque” está atrasada há 6 dias")
      expect(Notification.find_by(notifiable: without).user).to eq(owner)
      expect(Notification.where(kind: "task_late").count).to eq(2)
    end
  end
end
