# Módulos Tecnologia e Produtos: os mesmos dados do design (db/seeds/data/{technology,products}.yml).
# Pode rodar mais de uma vez: só cria o que ainda não existe.
module Seeds
  module Tecnologia
    DATA = Rails.root.join("db/seeds/data")
    # Nomes fictícios das assinaturas que o design só conta (não lista).
    BUSINESSES = %w[Oficina Mercado Escritório Loja Academia Agência Transportadora Restaurante Distribuidora Papelaria].freeze
    PLACES = [ "Central", "Horizonte", "Primavera", "Aurora", "Bela Vista", "Santa Clara", "Nova Era", "Sol Nascente", "Vale Azul", "Estrela" ].freeze
    FIRST_NAMES = %w[Ana Bruno Camila Daniel Elaine Fábio Gabriela Heitor Isabela João Karina Leonardo Mariana Nelson Olívia Pedro Renata Sérgio Tatiana Vítor].freeze
    LAST_NAMES = %w[Almeida Barros Cardoso Duarte Esteves Farias Gomes Lacerda Moura Pacheco Queiroz Ribeiro].freeze

    def self.load(file) = YAML.safe_load_file(DATA.join("#{file}.yml"))
    def self.company(name) = name && Company.find_by!(trade_name: name)
    def self.cents(value) = value && (value.to_d * 100).round

    def self.run
      data = load("technology")
      data["new_suppliers"].each { |row| Supplier.find_or_create_by!(name: row["name"]) { |s| s.assign_attributes(row.except("name")) } }

      servers = data["servers"].to_h do |row|
        server = Server.find_by(name: row["name"]) || Server.create!(
          row.except("company", "supplier", "monthly_cost").merge("company" => company(row["company"]), "supplier" => Supplier.find_by!(name: row["supplier"]),
                                                                  "monthly_cost_cents" => cents(row["monthly_cost"]))
        )
        [ server.name, server ]
      end

      services = data["external_services"].map do |row|
        attrs = row.slice("name", "plan", "currency", "periodicity", "paid_by", "vault_reference")
        service = ExternalService.find_by(name: row["name"], plan: row["plan"]) ||
                  ExternalService.create!(attrs.merge("supplier" => Supplier.find_by!(name: row["supplier"]), "company" => company(row["company"]), "cost_cents" => cents(row["cost"])))
        [ row, service ]
      end
      hostings = servers.merge(services.to_h { |row, service| [ row["key"], service ] }.compact)

      apps = data["apps"].to_h do |row|
        company = company(row["company"])
        app = company.apps.find_by(name: row["name"]) || company.apps.create!(
          row.slice("name", "description", "environment", "status", "url", "tech_stack", "repository_url", "vault_reference").merge(
            "hosting" => hostings[row["hosting"]], "project" => row["project"] && Project.find_by(name: row["project"]),
            "contract" => row["contract"] && Contract.find_by(number: row["contract"]), "user" => row["user"] && User.find_by(email: row["user"])
          )
        )
        Array(row["databases"]).each { |db| app.databases.find_or_create_by!(technology: db["technology"], environment: db["environment"]) { |d| d.assign_attributes(db) } }
        Array(row["integrations"]).each do |i|
          app.integrations.find_or_create_by!(platform: i["platform"], variant: i["variant"], environment: i["environment"]) { |r| r.assign_attributes(i) }
        end
        Ticket.where(number: row["tickets"], company: company, app_id: nil).find_each { |t| t.update!(app: app) } if row["tickets"]
        [ app.name, app ]
      end

      # Serviço externo ligado à aplicação e às contas a pagar (e à regra recorrente) do mesmo gasto.
      services.each do |row, service|
        service.update!(app: apps[row["app"]]) if row["app"] && service.app.nil?
        next unless row["payable"]

        RecurringExpense.where(description: row["payable"], external_service_id: nil).find_each { |rule| rule.update!(external_service: service) }
        Payable.where(description: row["payable"]).or(Payable.where("description LIKE ?", "#{Payable.sanitize_sql_like(row['payable'])} — %"))
               .where(external_service_id: nil).find_each { |p| p.update_columns(external_service_id: service.id) }
      end

      data["domains"].each do |row|
        next if Domain.exists?(name: row["name"])

        Domain.create!(row.except("company", "cost").merge("company" => company(row["company"]), "renewal_cost_cents" => cents(row["cost"]),
                                                           "currency" => row["currency"] || "BRL"))
      end

      products
    end

    def self.products
      data = load("products")
      months = (4..9).map { |m| Date.new(2026, m, 1) }
      data["products"].each do |row|
        product = Product.find_or_create_by!(name: row["name"]) { |p| p.assign_attributes(row.slice("url", "status", "description")) }
        row["costs"].each_with_index { |amount, i| product.costs.find_or_create_by!(month: months[i]) { |c| c.amount_cents = cents(amount) } }
        next if product.subscriptions.exists?

        seq = 0
        Array(row["growth"]).each do |month, count|
          start = Date.strptime(month, "%Y-%m")
          count.times do
            seq += 1
            value = row["plans"][seq % row["plans"].size]
            name, email = subscriber(product, seq)
            # A base de abril começou ao longo do 1º trimestre; os demais entram no próprio mês.
            started = month == "2026-04" ? Date.new(2026, 1 + (seq % 4), 1 + (seq * 7 % 27)) : start + (seq * 5 % 27)
            product.subscriptions.create!(subscriber_name: name, email: email, plan: plan_for(value), monthly_value_cents: value * 100, started_on: started, status: "active")
          end
        end
        row["beta"].to_i.times do |i|
          name, email = subscriber(product, 100 + i)
          product.subscriptions.create!(subscriber_name: name, email: email, plan: "Beta fechado", monthly_value_cents: 0, started_on: Date.new(2026, 9, 1 + i * 2), status: "trial",
                                        notes: "Convite do beta fechado")
        end
      end

      data["subscriptions"].each do |row|
        product = Product.find_by!(name: row["product"])
        next if product.subscriptions.exists?(subscriber_name: row["subscriber_name"])

        product.subscriptions.create!(row.except("product", "company", "value").merge("company" => company(row["company"]), "monthly_value_cents" => cents(row["value"])))
      end
    end

    def self.plan_for(value)
      { 49 => "Essencial", 79 => "Profissional", 149 => "Equipe", 30 => "Profissional" }.fetch(value, "Profissional")
    end

    # Nome e e-mail fictícios: empresas no CatalystOps, profissionais de saúde no PrescSign.
    def self.subscriber(product, seq)
      if product.name == "PrescSign"
        first = FIRST_NAMES[seq % FIRST_NAMES.size]
        last = LAST_NAMES[(seq / FIRST_NAMES.size + seq) % LAST_NAMES.size]
        title = first.end_with?("a") ? "Dra." : "Dr."
        [ "#{title} #{first} #{last}", "#{I18n.transliterate(first).downcase}.#{I18n.transliterate(last).downcase}@consultorio.med.br" ]
      else
        name = "#{BUSINESSES[seq % BUSINESSES.size]} #{PLACES[(seq / BUSINESSES.size + seq) % PLACES.size]}"
        [ name, "contato@#{I18n.transliterate(name).downcase.delete(' ')}.com.br" ]
      end
    end
  end
end

Seeds::Tecnologia.run
DomainAlertsJob.perform_now
