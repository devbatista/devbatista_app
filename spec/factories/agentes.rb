FactoryBot.define do
  factory :agent do
    sequence(:key) { |n| "agente#{n}" }
    sequence(:name) { |n| "Agente #{n}" }
    title { "SRE" }
    room { "Infra" }
    sequence(:position)
    outfit_color { "#0e7490" }
    hair_color { "#1f2937" }
    skin_color { "#e0ac69" }
  end

  factory :agent_event do
    agent
    status { "working" }
    sequence(:title) { |n| "Tarefa #{n}" }
    summary { "O que foi feito." }

    trait :approval do
      status { "awaiting_approval" }
      title { "Enviar follow-up" }
    end
  end

  factory :agent_order do
    agent
    user
    body { "Priorize os leads do site." }
  end
end
