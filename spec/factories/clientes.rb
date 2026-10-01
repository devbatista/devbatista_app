FactoryBot.define do
  factory :company do
    sequence(:trade_name) { |n| "Empresa #{n}" }
    legal_name { "#{trade_name} Ltda." }
    sequence(:cnpj) { |n| CnpjHelper.generate(10_000 + n) }
    status { "active" }
  end

  factory :contact do
    company
    sequence(:name) { |n| "Contato #{n}" }
    position { "Gerente" }
  end

  factory :service do
    sequence(:name) { |n| "Serviço #{n}" }
    category { "Consultoria" }
    kind { "recurring" }
    default_price_cents { 100_000 }
  end

  factory :contract do
    company
    title { "Suporte" }
    status { "active" }
    start_date { Date.current - 6.months }
    end_date { Date.current + 6.months }
    value_cents { 100_000 }
  end

  factory :customer_service do
    company
    service
    price_cents { 100_000 }
    recurrence { "monthly" }
    start_date { Date.current - 1.month }
    due_day { 10 }
  end

  factory :document do
    company
    documentable { company }
    title { "contrato.pdf" }
    kind { "contract" }
    uploaded_by factory: :user
    after(:build) { |doc| doc.file.attach(io: StringIO.new("%PDF-1.4"), filename: "contrato.pdf", content_type: "application/pdf") }
  end
end
