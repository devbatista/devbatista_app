FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "Pessoa #{n}" }
    sequence(:email) { |n| "pessoa#{n}@devbatista.com" }
    password { "senha-segura-123" }
    password_confirmation { password }
    role factory: %i[role admin]

    Role::DEFAULTS.each_key do |role_key|
      trait(role_key.to_sym) { role factory: [ :role, role_key.to_sym ] }
    end

    trait(:inactive) { active { false } }
  end
end
