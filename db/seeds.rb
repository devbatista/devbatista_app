# Perfis com a matriz inicial e a equipe usada no design (docs/design/administracao/usuarios.html).
# Pode rodar mais de uma vez: só cria o que ainda não existe.
Role.seed_defaults!

password = ENV.fetch("SEED_PASSWORD") { Rails.env.production? ? raise("Defina SEED_PASSWORD") : "devbatista123" }

team = [
  [ "Rafael Batista", "rafael@devbatista.com.br", "admin", nil ],
  [ "Ana Souza", "ana.souza@devbatista.com.br", "comercial", nil ],
  [ "Bruno Lima", "bruno.lima@devbatista.com.br", "financeiro", 70 ],
  [ "Carla Mendes", "carla.mendes@devbatista.com.br", "suporte", 65 ],
  [ "Diego Rocha", "diego.rocha@devbatista.com.br", "desenvolvedor", 95 ],
  [ "Elisa Prado", "elisa.prado@devbatista.com.br", "desenvolvedor", 90 ]
]
team = team.first(1) if Rails.env.production?

team.each do |name, email, role_key, hourly_cost|
  User.find_or_create_by!(email: email) do |user|
    user.name = name
    user.role = Role.find_by!(key: role_key)
    user.hourly_cost = hourly_cost
    user.password = user.password_confirmation = password
  end
end

# Dados de negócio do design só fora de produção.
unless Rails.env.production?
  load Rails.root.join("db/seeds/clientes.rb")
  load Rails.root.join("db/seeds/comercial.rb")
  load Rails.root.join("db/seeds/operacao.rb")
end

puts "Perfis: #{Role.count} · Usuários: #{User.count}"
puts "Empresas: #{Company.count} · Contatos: #{Contact.count} · Contratos: #{Contract.count} · " \
     "Serviços contratados: #{CustomerService.count} · MRR: R$ #{CustomerService.active.sum(:mrr_cents) / 100}" unless Rails.env.production?
puts "Leads: #{Lead.count} · Oportunidades: #{Opportunity.count} · Propostas: #{Proposal.count} · " \
     "Ponderada em aberto: R$ #{Opportunity.open.sum(&:weighted_cents) / 100}" unless Rails.env.production?
puts "Projetos: #{Project.count} (atrasados: #{Project.late.count}) · Tarefas: #{Task.count} · Horas: #{TimeEntry.sum(:minutes) / 60}h em " \
     "#{TimeEntry.count} lançamentos · Chamados: #{Ticket.count} (#{Ticket.open.count} abertos)" unless Rails.env.production?
puts "Senha dos usuários de exemplo: #{password}" unless Rails.env.production?
