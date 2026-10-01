# Módulo Clientes: os mesmos dados mostrados no design (db/seeds/data/*.yml, extraídos de docs/design).
# Pode rodar mais de uma vez: só cria o que ainda não existe.
module Seeds
  module Clientes
    DATA = Rails.root.join("db/seeds/data")

    def self.load(file)
      YAML.safe_load_file(DATA.join("#{file}.yml"))
    end

    def self.run
      services = load("services").to_h do |row|
        service = Service.find_or_create_by!(name: row["name"]) { |s| s.assign_attributes(row.except("name")) }
        [ service.name, service ]
      end

      companies = load("companies").to_h do |row|
        company = Company.find_by(cnpj: row["cnpj"].gsub(/\D/, "")) || Company.create!(row)
        [ company.trade_name, company ]
      end

      load("contacts").each do |row|
        company = companies.fetch(row["company"])
        company.contacts.find_or_create_by!(name: row["name"]) { |c| c.assign_attributes(row.except("company", "name")) }
      end

      contracts = load("contracts").to_h do |row|
        contract = Contract.find_by(number: row["number"]) ||
                   Contract.create!(row.except("company").merge("company" => companies.fetch(row["company"])))
        [ contract.number, contract ]
      end
      # Próximo número livre depois dos contratos do design.
      ActiveRecord::Base.connection.execute("SELECT setval('contract_numbers', #{Contract.maximum(:number)})")

      load("customer_services").each do |row|
        company = companies.fetch(row["company"])
        service = services.fetch(row["service"])
        next if CustomerService.exists?(company: company, service: service, price_cents: (row["price"] * 100).round)

        CustomerService.create!(
          row.except("company", "service", "contract").merge(
            "company" => company, "service" => service, "contract" => contracts[row["contract"]],
            "start_date" => row["start_date"] || company.customer_since || Date.new(2026, 1, 1)
          )
        )
      end

      load("documents").each do |row|
        next if Document.exists?(title: row["title"])

        link = contracts[row["contract"]] || companies[row["company"]]
        document = Document.new(title: row["title"], kind: row["kind"], documentable: link, notes: row["notes"],
                                uploaded_by: User.find_by(email: row["uploaded_by"]) || User.first,
                                created_at: row["uploaded_at"])
        document.file.attach(io: StringIO.new(placeholder_pdf(row["title"])), filename: row["title"], content_type: "application/pdf")
        document.save!
      end
    end

    # PDF mínimo de uma página, só para o arquivo de exemplo abrir no navegador.
    def self.placeholder_pdf(title)
      text = "Documento de exemplo: #{title}".encode("ASCII", invalid: :replace, undef: :replace, replace: "?").gsub(/[()\\]/, "")
      stream = "BT /F1 14 Tf 72 760 Td (#{text}) Tj ET"
      objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
      ]
      pdf = +"%PDF-1.4\n"
      offsets = objects.each_with_index.map do |body, i|
        offset = pdf.bytesize
        pdf << "#{i + 1} 0 obj\n#{body}\nendobj\n"
        offset
      end
      xref = pdf.bytesize
      pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
      offsets.each { |o| pdf << format("%010d 00000 n \n", o) }
      pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    end
  end
end

Seeds::Clientes.run

# Roda a rotina diária uma vez: atualiza os status de vencimento e gera os alertas de hoje.
ContractAlertsJob.perform_now
