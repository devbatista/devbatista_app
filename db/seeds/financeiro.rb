# Módulo Financeiro: os mesmos dados do design (db/seeds/data/{suppliers,payables,receivables,invoices}.yml).
# Pode rodar mais de uma vez: só cria o que ainda não existe.
module Seeds
  module Financeiro
    DATA = Rails.root.join("db/seeds/data")
    SEPTEMBER = Date.new(2026, 9, 1)
    HISTORY = Date.new(2026, 4, 1)..Date.new(2026, 8, 31) # meses pagos, para o gráfico de 6 meses
    USD = 5.62 # câmbio usado no design

    def self.load(file) = YAML.safe_load_file(DATA.join("#{file}.yml"))
    def self.company(name) = name && Company.find_by!(trade_name: name)
    def self.cents(value) = value && (value.to_d * 100).round

    def self.run
      [ Date.new(2026, 9, 3), Date.new(2026, 9, 17) ].each do |day|
        ExchangeRate.find_or_create_by!(currency: "USD", quoted_on: day) { |r| r.rate = USD }
      end

      suppliers = load("suppliers").to_h do |row|
        [ row["name"], Supplier.find_or_create_by!(name: row["name"]) { |s| s.assign_attributes(row.except("name")) } ]
      end

      load("payables").each { |row| create_payable(row, suppliers.fetch(row["supplier"])) }
      load("receivables").each { |row| create_receivable(row) }
      history
      load("invoices").each { |row| create_invoice(row) }
    end

    def self.create_payable(row, supplier)
      rule = rule_for(row, supplier) if row["recurring"]
      return if Payable.exists?(supplier: supplier, description: row["description"], competence: SEPTEMBER) ||
                (rule && rule.payables.exists?(competence: SEPTEMBER))

      Payable.create!(supplier: supplier, recurring_expense: rule, description: row["description"], category: row["category"],
                      currency: row["currency"] || "BRL", original_amount_cents: cents(row["original"]), amount_cents: cents(row["amount"]),
                      exchange_rate: row["original"] && (row["amount"].to_d / row["original"].to_d).round(4),
                      competence: SEPTEMBER, due_on: row["due_on"], paid_on: row["paid_on"], status: row["status"] || "paid",
                      company: company(row["company"]), cost_center: row["cost_center"])
    end

    def self.rule_for(row, supplier)
      rec = row["recurring"]
      supplier.recurring_expenses.find_by(description: row["description"]) ||
        supplier.recurring_expenses.create!(description: row["description"], category: row["category"], currency: row["currency"] || "BRL",
                                            amount_cents: cents(row["original"] || row["amount"]), periodicity: rec["periodicity"] || "monthly",
                                            due_day: rec["due_day"], start_on: rec["start_on"] || HISTORY.first.change(day: [ rec["due_day"], 28 ].min),
                                            company: company(row["company"]), cost_center: row["cost_center"],
                                            status: rec["ended_on"] ? "ended" : "active", ended_on: rec["ended_on"])
    end

    def self.create_receivable(row)
      company = company(row["company"])
      service = Service.find_by!(name: row["service"])
      customer_service = company.customer_services.find_by!(service: service) if row["recurring"]
      return if Receivable.exists?(company: company, description: row["description"], competence: SEPTEMBER)

      Receivable.create!(company: company, service: service, customer_service: customer_service, description: row["description"],
                         category: service.name, amount_cents: cents(row["amount"]), competence: SEPTEMBER, due_on: row["due_on"],
                         paid_on: row["paid_on"], paid_amount_cents: row["paid_on"] && cents(row["amount"]),
                         status: row["status"] || "paid", notes: row["notes"])
    end

    # Setembro dos demais serviços contratados (pago) e abril a agosto de tudo (pago no vencimento).
    def self.history
      CustomerService.recurring.where.not(status: "suspended").includes(:service, :company).find_each do |cs|
        months = CustomerService::PERIOD_MONTHS[cs.recurrence]
        last = [ cs.ended_on, SEPTEMBER.end_of_month ].compact.min
        RecurrenceRoutine.due_dates(cs.start_date, months, cs.due_day, HISTORY.first, last).each do |due_on|
          next if cs.receivables.exists?(competence: due_on.beginning_of_month)

          cs.receivables.create!(company: cs.company, description: "#{cs.service.name} — #{I18n.l(due_on, format: '%B/%Y').capitalize}",
                                 category: cs.service.name, amount_cents: cs.price_cents, competence: due_on.beginning_of_month,
                                 due_on: due_on, paid_on: due_on, paid_amount_cents: cs.price_cents, status: "paid")
        end
      end

      RecurringExpense.includes(:supplier).find_each do |rule|
        rule.due_dates(HISTORY.first, HISTORY.last).each do |due_on|
          next if rule.payables.exists?(competence: due_on.beginning_of_month)

          attrs = rule.payable_attributes(due_on)
          attrs[:amount_cents] = (attrs[:original_amount_cents] * USD).round if rule.foreign?
          rule.payables.create!(attrs.merge(paid_on: due_on, status: "paid", exchange_rate: (USD if rule.foreign?)))
        end
      end
    end

    def self.create_invoice(row)
      return if Invoice.exists?(number: row["number"])

      company = company(row["company"])
      invoice = Invoice.new(company: company, number: row["number"], description: row["description"], amount_cents: cents(row["amount"]),
                            competence: SEPTEMBER, issued_on: row["issued_on"], status: row["status"], url: row["url"])
      Array(row["files"]).each do |kind|
        name = "NFS-e #{row['number']} #{company.trade_name}.#{kind}"
        body = kind == "pdf" ? Seeds::Clientes.placeholder_pdf(name) : %(<?xml version="1.0"?><nfse><numero>#{row['number']}</numero></nfse>)
        invoice.files.attach(io: StringIO.new(body), filename: name, content_type: kind == "pdf" ? "application/pdf" : "application/xml")
      end
      invoice.save!
      Receivable.where(company: company, competence: SEPTEMBER).find_each do |r|
        r.update!(invoice: invoice) if load("receivables").any? { |x| x["invoice"] == row["number"] && x["description"] == r.description && x["company"] == row["company"] }
      end
    end
  end
end

Seeds::Financeiro.run
RecurrenceRoutine.new.run!
