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

  factory :fiscal_invoice do
    company
    number { generate(:fiscal_invoice_number) }
    status { "issued" }
    competence { Date.current.beginning_of_month }
    issued_on { Date.current }
    amount_cents { 380_000 }
  end

  # Rascunho com uma receita do mesmo cliente; :issued emite (número e receitas ligadas).
  factory :invoice do
    company
    due_on { Date.current + 7 }

    after(:build) do |invoice|
      invoice.receivable_ids_for_items = [ create(:receivable, company: invoice.company).id ] if invoice.items.empty?
    end

    trait :issued do
      after(:create) { |invoice| invoice.issue! }
    end
  end

  factory :billing_connection do
    supplier
    provider { "aws" }
    sequence(:name) { |n| "AWS #{n}" }
    sequence(:account_id) { |n| format("%012d", 123_456_789_000 + n) }
    cost_center { "Infraestrutura interna" }
  end

  sequence(:fiscal_invoice_number) { |n| format("%06d", 400 + n) }
end
