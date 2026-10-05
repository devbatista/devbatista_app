FactoryBot.define do
  factory :server do
    company
    supplier
    sequence(:name) { |n| "app-server-#{n}" }
    host { "18.231.44.12" }
    environment { "production" }
    os { "Ubuntu 24.04 LTS" }
    monthly_cost_cents { 22_000 }
  end

  factory :app do
    company
    sequence(:name) { |n| "Aplicação #{n}" }
    environment { "production" }
    status { "active" }
  end

  factory :external_service do
    supplier
    company
    name { "Railway" }
    currency { "USD" }
    cost_cents { 2_669 }
    periodicity { "monthly" }
    paid_by { "devbatista" }
  end

  factory :database do
    app
    technology { "PostgreSQL" }
    version { "16.4" }
    environment { "production" }
  end

  factory :integration do
    app
    platform { "OpenAI" }
    purpose { "Resumo automático de chamados" }
    environment { "production" }
    status { "active" }
  end

  factory :domain do
    company
    sequence(:name) { |n| "dominio#{n}.com.br" }
    registrar { "Registro.br" }
    expires_on { Date.current + 200 }
    renewal_cost_cents { 4_000 }
  end

  factory :product do
    sequence(:name) { |n| "Produto #{n}" }
    status { "operating" }
  end

  factory :subscription do
    product
    sequence(:subscriber_name) { |n| "Assinante #{n}" }
    plan { "Profissional" }
    monthly_value_cents { 7_900 }
    started_on { Date.current - 90 }
    status { "active" }
  end
end
