# Módulo Operação: os mesmos dados do design (db/seeds/data/{projects,tasks,tickets,time_entries}.yml).
# Pode rodar mais de uma vez: só cria o que ainda não existe.
module Seeds
  module Operacao
    DATA = Rails.root.join("db/seeds/data")
    DESIGN_TODAY = Date.new(2026, 9, 17) # "hoje" nas telas do design
    CHUNK = 6 * 60 # lançamentos completados pelo seed: até 6 h por dia útil

    def self.load(file) = YAML.safe_load_file(DATA.join("#{file}.yml"))
    def self.user(email) = User.find_by(email: email) || User.first
    def self.company(name) = Company.find_by!(trade_name: name)
    def self.minutes(hours) = (hours.to_f * 60).round

    def self.run
      project_rows = load("projects")
      projects = project_rows.to_h do |row|
        project = Project.find_by(name: row["name"]) || Project.create!(
          row.slice("name", "status", "start_date", "due_date", "closed_on", "budget", "progress", "progress_from_tasks", "description").merge(
            "company" => company(row["company"]), "user" => user(row["user"]),
            "contract" => row["contract"] && Contract.find_by(number: row["contract"]),
            "proposal" => row["proposal"] && Proposal.find_by(year: row["proposal"].to_s.split("-").first, number: row["proposal"].to_s.split("-").last)
          )
        )
        [ project.name, project ]
      end

      tasks = load("tasks").to_h do |row|
        project = projects.fetch(row["project"])
        task = project.tasks.find_by(title: row["title"]) || project.tasks.create!(
          row.slice("title", "status", "priority", "due_on", "completed_on").merge("user" => user(row["user"]), "estimated_minutes" => minutes(row["estimate"]))
        )
        [ task.title, [ task, row ] ]
      end

      tickets = load("tickets").to_h do |row|
        ticket = Ticket.find_by(number: row["number"]) || create_ticket(row)
        [ ticket.number, ticket ]
      end
      # Próximo número livre depois dos chamados do design.
      ActiveRecord::Base.connection.execute("SELECT setval('ticket_numbers', #{Ticket.maximum(:number)})") if Ticket.exists?

      load("time_entries").each do |row|
        worked_on = Date.parse(row["date"])
        next if TimeEntry.exists?(user: user(row["user"]), worked_on: worked_on, description: row["description"])

        TimeEntry.create!(user: user(row["user"]), worked_on: worked_on, duration: row["duration"], description: row["description"],
                          company: company(row["company"]), project: projects[row["project"]], task: tasks.dig(row["task"], 0),
                          ticket: tickets[row["ticket"]])
      end

      # Completa as horas registradas de cada tarefa e de cada projeto até os totais do design.
      tasks.each_value do |task, row|
        missing = minutes(row["logged"]) - task.time_entries.sum(:minutes)
        before = task.completed_on ? task.completed_on + 1 : [ task.due_on, DESIGN_TODAY ].compact.min
        fill!(missing, before: before, user: task.user || task.project.user, company: task.project.company, project: task.project,
                       task: task, description: "Desenvolvimento — #{task.title}")
      end
      project_rows.each do |row|
        project = projects.fetch(row["name"])
        missing = minutes(row["hours"]) - project.time_entries.sum(:minutes)
        fill!(missing, before: row["hours_until"] ? Date.parse(row["hours_until"]) : DESIGN_TODAY, user: project.user, company: project.company,
                       project: project, description: row["hours_description"] || "Desenvolvimento — #{project.name}")
      end
    end

    def self.create_ticket(row)
      company = company(row["company"])
      contact = ->(name) { name && company.contacts.find_by!(name: name) }
      ticket = Ticket.create!(row.slice("number", "subject", "description", "category", "priority", "status", "opened_at", "resolved_at").merge(
        "company" => company, "user" => user(row["user"]), "contact" => contact.call(row["contact"])
      ))
      # Horários do fluxo mostrados no design, gravados na trilha de auditoria.
      (row["steps"] || {}).each_with_object([ "open" ]) do |(status, at), previous|
        AuditLog.create!(action: "status_change", area: "suporte", auditable: ticket, auditable_label: ticket.to_s, user: ticket.user,
                         changeset: { "status" => [ previous.last, status ] }, created_at: at)
        previous << status
      end
      (row["messages"] || []).each do |m|
        ticket.messages.create!(kind: m["kind"], body: m["body"], channel: m["channel"], user: user(m["user"]),
                                contact: contact.call(m["contact"]), created_at: m["at"], updated_at: m["at"])
      end
      ticket
    end

    # Lança `minutes` em blocos de até 6 h, em dias úteis anteriores a `before`.
    def self.fill!(minutes, before:, **attrs)
      date = before - 1
      while minutes.positive?
        date -= 1 while date.saturday? || date.sunday?
        chunk = [ minutes, CHUNK ].min
        TimeEntry.create!(worked_on: date, minutes: chunk, **attrs)
        minutes -= chunk
        date -= 1
      end
    end
  end
end

Seeds::Operacao.run
OperationAlertsJob.perform_now
