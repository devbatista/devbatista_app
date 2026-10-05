FactoryBot.define do
  factory :supplier do
    sequence(:name) { |n| "Fornecedor #{n}" }
    category { "Infraestrutura" }
  end

  factory :receivable do
    company
    description { "Consultoria de TI — Setembro/2026" }
    category { "Consultoria de TI" }
    amount_cents { 300_000 }
    competence { Date.current.beginning_of_month }
    due_on { Date.current + 5 }
  end

  factory :payable do
    supplier
    description { "Hospedagem — Sistema ERP" }
    category { "Infraestrutura" }
    cost_center { "Administrativo" }
    amount_cents { 65_000 }
    competence { Date.current.beginning_of_month }
    due_on { Date.current + 5 }
  end

  factory :recurring_expense do
    supplier
    description { "Honorários contábeis" }
    category { "Contabilidade" }
    cost_center { "Administrativo" }
    amount_cents { 65_000 }
    due_day { 20 }
    start_on { Date.current.beginning_of_month }
  end

  factory :invoice do
    company
    number { generate(:invoice_number) }
    status { "issued" }
    competence { Date.current.beginning_of_month }
    issued_on { Date.current }
    amount_cents { 380_000 }
  end

  sequence(:invoice_number) { |n| format("%06d", 400 + n) }
end
