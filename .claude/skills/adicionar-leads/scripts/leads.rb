# Executado pela skill adicionar-leads com bin/rails runner.
# PAYLOAD (Hash) é definido por run.sh antes deste trecho.
#
#   mode: "lookup"  lista usuários, serviços, origens, status e leads já cadastrados
#   mode: "create"  cria os leads numa transação; com dry_run, desfaz no final

FIELDS = %w[name company_name email phone whatsapp origin service_id user_id status
            entered_on notes next_step next_step_on].freeze
STATUSES = %w[new contacted qualified].freeze

def lookup(payload)
  puts "== Usuários ativos (id | nome | e-mail)"
  User.active.by_name.each { |user| puts "#{user.id} | #{user.name} | #{user.email}" }

  puts "\n== Serviços disponíveis (id | nome)"
  Service.available.each { |service| puts "#{service.id} | #{service.name}" }

  puts "\n== Origens (valor | rótulo)"
  Lead::ORIGIN_LABELS.each { |value, label| puts "#{value} | #{label}" }

  puts "\n== Status (valor | rótulo)"
  Lead::STATUS_LABELS.slice(*STATUSES).each { |value, label| puts "#{value} | #{label}" }

  emails = Array(payload["emails"]).map { |email| email.to_s.strip.downcase }.reject(&:empty?)
  names = Array(payload["names"]).map { |name| name.to_s.strip }.reject(&:empty?)
  found = Lead.where(email: emails).to_a
  names.each do |name|
    found += Lead.where("unaccent(leads.name) ILIKE unaccent(:q) OR unaccent(leads.company_name) ILIKE unaccent(:q)",
                        q: Lead.sanitize_sql_like(name)).to_a
  end

  puts "\n== Já cadastrados (id | nome | empresa | e-mail | status)"
  puts "nenhum" if found.empty?
  found.uniq.sort_by(&:id).each do |lead|
    puts [ lead.id, lead.name, lead.company_name, lead.email, lead.status_label ].join(" | ")
  end
end

def create(payload)
  defaults = payload.fetch("defaults", {}).slice(*FIELDS)
  Current.user = User.active.find(defaults.fetch("user_id"))
  rows = payload.fetch("leads")

  Lead.transaction do
    rows.each do |row|
      attrs = defaults.merge(row.slice(*FIELDS))
      unless attrs.fetch("status", "new").in?(STATUSES)
        raise ArgumentError, "status #{attrs['status']} não é aceito (use #{STATUSES.join(', ')})"
      end

      lead = Lead.create!(attrs)
      puts [ lead.id, lead.name, lead.company_name, lead.email, lead.origin_label,
             lead.service&.name || "a definir", lead.user.name, lead.status_label ].join(" | ")
    end

    if payload.fetch("dry_run", true)
      puts "\nSIMULAÇÃO OK: #{rows.size} leads válidos, nada foi gravado."
      raise ActiveRecord::Rollback
    end
    puts "\nGRAVADO: #{rows.size} leads. Total de leads: #{Lead.count}."
  end
end

begin
  case PAYLOAD.fetch("mode")
  when "lookup" then lookup(PAYLOAD)
  when "create" then create(PAYLOAD)
  else raise ArgumentError, "mode deve ser lookup ou create"
  end
rescue ActiveRecord::RecordInvalid => e
  puts "ERRO em #{e.record.name.inspect}: #{e.record.errors.full_messages.to_sentence}. Nada foi gravado."
rescue ActiveRecord::RecordNotFound, ArgumentError, KeyError => e
  puts "ERRO: #{e.message}. Nada foi gravado."
end
