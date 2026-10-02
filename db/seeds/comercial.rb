# Módulo Comercial: os mesmos dados do design (db/seeds/data/{leads,opportunities,proposals,interactions}.yml).
# Pode rodar mais de uma vez: só cria o que ainda não existe.
module Seeds
  module Comercial
    DATA = Rails.root.join("db/seeds/data")

    def self.load(file) = YAML.safe_load_file(DATA.join("#{file}.yml"))
    def self.user(email) = User.find_by(email: email) || User.first
    def self.company(name) = name && Company.find_by!(trade_name: name)
    def self.service(name) = name && Service.find_by!(name: name)

    def self.run
      leads = load("leads").to_h do |row|
        lead = Lead.find_by(name: row["name"], company_name: row["company_name"]) ||
               Lead.create!(row.except("service", "user", "company").merge(
                 "service" => service(row["service"]), "user" => user(row["user"]), "company" => company(row["company"])
               ))
        [ lead.name, lead ]
      end

      opportunities = load("opportunities").to_h do |row|
        opp = Opportunity.find_by(title: row["title"]) ||
              Opportunity.create!(row.except("company", "lead", "service", "user").merge(
                "company" => company(row["company"]), "lead" => leads[row["lead"]], "service" => service(row["service"]), "user" => user(row["user"])
              ))
        [ opp.title, opp ]
      end

      # Lead que já tem oportunidade foi convertido: o pipeline mostra só a oportunidade (regra do doc. 08).
      opportunities.each_value do |opp|
        lead = opp.lead
        lead.update!(status: "converted", company: opp.company, converted_at: lead.converted_at || opp.created_at) if lead&.open?
      end

      load("proposals").each do |row|
        next if Proposal.exists?(year: row["year"], number: row["number"])

        items = row["items"].each_with_index.map do |item, i|
          { service: service(item["service"]), description: item["description"], recurrence: item["recurrence"],
            price: item["price"], default_price: item["default_price"], position: i }
        end
        proposal = Proposal.new(row.except("company", "lead", "opportunity", "contact", "user", "contract", "items").merge(
          "company" => company(row["company"]), "lead" => leads[row["lead"]], "opportunity" => opportunities[row["opportunity"]],
          "contact" => row["contact"] && Contact.find_by(name: row["contact"]), "user" => user(row["user"]),
          "contract" => row["contract"] && Contract.find_by(number: row["contract"])
        ))
        items.each { |attrs| proposal.items.build(attrs) }
        proposal.save!
      end

      load("interactions").each do |row|
        subject = row["subject_type"] == "Lead" ? leads[row["subject"]] : opportunities[row["subject"]]
        next if subject.nil? || subject.interactions.exists?(occurred_on: row["occurred_on"], kind: row["kind"])

        subject.interactions.create!(kind: row["kind"], occurred_on: row["occurred_on"], notes: row["notes"], user: user(row["user"]))
      end
    end
  end
end

Seeds::Comercial.run
ProposalAlertsJob.perform_now
