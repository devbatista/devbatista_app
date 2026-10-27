FactoryBot.define do
  factory :whatsapp_account do
    business_id { "106724254821671" }
    sequence(:waba_id) { |n| "10293847561#{n.to_s.rjust(5, '0')}" }
    sequence(:phone_number_id) { |n| "66554433221#{n.to_s.rjust(5, '0')}" }
    display_phone_number { "+55 11 97070-2026" }
    verified_name { "DevBatista" }
    access_token { "token-de-acesso-de-teste" }
    status { "connected" }
    coexistence { true }
  end

  factory :whatsapp_conversation do
    account factory: :whatsapp_account
    sequence(:bsuid) { |n| "BR.#{n.to_s.rjust(20, '7')}" }
    sequence(:wa_id) { |n| "5511991#{n.to_s.rjust(6, '0')}" }
    profile_name { "Henrique Duarte" }
  end

  factory :whatsapp_message do
    conversation factory: :whatsapp_conversation
    direction { "inbound" }
    origin { "contact" }
    status { "received" }
    kind { "text" }
    body { "Bom dia! Quando podemos conversar?" }
    sequence(:wa_message_id) { |n| "wamid.TESTE#{n}" }
    sent_at { Time.current }

    trait :outbound do
      direction { "outbound" }
      origin { "admin" }
      status { "sent" }
      user
    end

    trait :reaction do
      kind { "reaction" }
      body { nil }
      reaction_emoji { "👍" }
      reaction_to_wa_message_id { association(:whatsapp_message, :outbound, conversation: conversation).wa_message_id }
    end
  end

  factory :whatsapp_template do
    account factory: :whatsapp_account
    sequence(:name) { |n| "lembrete_proposta_#{n}" }
    language { "pt_BR" }
    category { "utility" }
    status { "approved" }
    components { [ { "type" => "BODY", "text" => "Olá, {{1}}. A proposta {{2}} vence em {{3}}." } ] }
  end
end
