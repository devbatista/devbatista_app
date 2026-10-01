FactoryBot.define do
  factory :role do
    sequence(:key) { |n| "perfil_#{n}" }
    name { key.humanize }
    permissions { {} }

    Role::DEFAULTS.each do |role_key, attrs|
      trait(role_key.to_sym) do
        key { role_key }
        name { attrs[:name] }
        permissions { attrs[:permissions] }
        initialize_with { Role.find_or_initialize_by(key: role_key) }
      end
    end
  end
end
