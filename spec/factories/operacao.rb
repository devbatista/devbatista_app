FactoryBot.define do
  factory :project do
    company
    user
    name { "Portal ACME — Fase 2" }
    status { "in_progress" }
    start_date { Date.current - 30 }
    due_date { Date.current + 30 }
    budget_cents { 2_400_000 }
  end

  factory :task do
    project
    sequence(:title) { |n| "Tarefa #{n}" }
    status { "todo" }
    priority { "normal" }
  end

  factory :time_entry do
    user
    company
    worked_on { Date.current }
    minutes { 90 }
  end

  factory :ticket do
    company
    subject { "Erro ao gerar relatório" }
    description { "O relatório de pedidos retorna erro 500." }
    category { "bug" }
    priority { "normal" }
  end
end
