FactoryBot.define do
  factory :lead do
    sequence(:name) { |n| "Pessoa Lead #{n}" }
    company_name { "Empresa do lead" }
    origin { "site" }
    user
  end

  factory :opportunity do
    company
    user
    title { "Novo portal" }
    stage { "meeting" }
    estimated_value_cents { 1_000_000 }
    expected_close_on { Date.current + 30 }
  end

  factory :proposal do
    company
    user
    title { "Portal de Pedidos" }
    valid_until { Date.current + 15 }
    after(:build) do |proposal|
      proposal.items.build(service: create(:service, default_price_cents: 300_000), price_cents: 300_000, recurrence: "monthly") if proposal.items.empty?
    end
  end
end
