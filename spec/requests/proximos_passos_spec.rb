require "rails_helper"

RSpec.describe "Comercial → Próximos passos" do
  let(:now) { Time.zone.local(2026, 11, 11, 10) } # quarta-feira
  let(:comercial) { create(:user, :comercial) }

  around { |example| travel_to(now) { example.run } }

  before { sign_in comercial }

  it "mostra leads e oportunidades em aberto por grupo, com os filtros" do
    create(:lead, name: "Ana Atrasada", next_step: "Ligar de volta", next_step_on: now - 1.day, whatsapp: "11 98888-7777")
    create(:opportunity, title: "Portal Hoje", next_step: "Reunião técnica", next_step_on: now + 2.hours)
    create(:lead, name: "Eva Sem Data")
    create(:lead, name: "Fora Convertido", status: "converted", next_step_on: now)

    get next_steps_path
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("Atrasados", "Ana Atrasada", "Ligar de volta", "https://wa.me/5511988887777", "Hoje", "Portal Hoje",
                            "12:00", "Sem próximo passo", "Eva Sem Data")
    expect(body).not_to include("Fora Convertido")
    expect(body.index("Ana Atrasada")).to be < body.index("Portal Hoje")

    get next_steps_path(periodo: "hoje")
    expect(response.body).to include("Portal Hoje")
    expect(response.body).not_to include("Ana Atrasada")

    get next_steps_path(tipo: "lead")
    expect(response.body).to include("Ana Atrasada")
    expect(response.body).not_to include("Portal Hoje")
  end

  it "aparece no menu do Comercial" do
    get next_steps_path
    expect(response.body).to include(%(href="#{next_steps_path}"))
  end

  describe "Feito" do
    let(:lead) { create(:lead, next_step: "Ligar", next_step_on: now - 1.hour) }

    it "abre o formulário na gaveta" do
      get done_lead_next_step_path(lead)
      expect(response.body).to include("Marcar como feito", "O que foi feito", "Marcar como perdido", "Preço")
    end

    it "grava a interação e o novo próximo passo e volta para a lista com os filtros" do
      post done_lead_next_step_path(lead, periodo: "atrasados"), params: { completion: {
        kind: "whatsapp", notes: "Mandei o diagnóstico", outcome: "next_step", next_step: "Cobrar retorno", next_step_on: "2026-11-13T14:30"
      } }
      expect(response).to redirect_to(next_steps_path(periodo: "atrasados"))
      expect(lead.reload).to have_attributes(next_step: "Cobrar retorno", next_step_on: Time.zone.local(2026, 11, 13, 14, 30))
      expect(lead.interactions.sole).to have_attributes(kind: "whatsapp", notes: "Mandei o diagnóstico", user: comercial)
    end

    it "marca como perdido com o motivo" do
      post done_lead_next_step_path(lead), params: { completion: { kind: "call", notes: "Sem orçamento este ano", outcome: "lost", lost_reason: "Sem orçamento" } }
      expect(lead.reload).to have_attributes(status: "lost", lost_reason: "Sem orçamento")
      expect(lead.interactions.count).to eq(1)
    end

    it "recusa sem próximo passo nem perdido e não grava nada" do
      post done_lead_next_step_path(lead), params: { completion: { kind: "call", notes: "Liguei", outcome: "next_step", next_step: "", next_step_on: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Próximo passo não pode ficar em branco")
      expect(lead.reload.next_step).to eq("Ligar")
      expect(Interaction.count).to eq(0)
    end

    it "funciona na oportunidade e volta para a ficha do lead quando veio de lá" do
      opportunity = create(:opportunity, next_step_on: now)
      post done_opportunity_next_step_path(opportunity), params: { completion: {
        kind: "meeting", notes: "Reunião feita", outcome: "next_step", next_step: "Enviar proposta", next_step_on: "2026-11-12"
      } }
      expect(opportunity.reload.next_step_on).to eq(Time.zone.local(2026, 11, 12, 9))

      post done_lead_next_step_path(lead, voltar: "ficha"), params: { completion: { kind: "note", notes: "Ok", outcome: "lost", lost_reason: "Prazo" } }
      expect(response).to redirect_to(lead_path(lead))
    end
  end

  describe "Adiar" do
    let(:lead) { create(:lead, next_step: "Ligar", next_step_on: now - 1.hour) }

    it "adia pelos atalhos e por data e hora escolhida" do
      get postpone_lead_next_step_path(lead)
      expect(response.body).to include("+1 hora", "Amanhã, 9h", "Próxima segunda, 9h")

      { "1h" => Time.zone.local(2026, 11, 11, 11), "amanha" => Time.zone.local(2026, 11, 12, 9),
        "segunda" => Time.zone.local(2026, 11, 16, 9) }.each do |option, expected|
        patch postpone_lead_next_step_path(lead), params: { para: option }
        expect(lead.reload.next_step_on).to eq(expected)
      end

      patch postpone_lead_next_step_path(lead, tipo: "lead"), params: { para: "escolher", em: "2026-11-20T16:45" }
      expect(response).to redirect_to(next_steps_path(tipo: "lead"))
      expect(lead.reload.next_step_on).to eq(Time.zone.local(2026, 11, 20, 16, 45))
      expect(Interaction.count).to eq(0)
    end

    it "pede a data quando ela falta" do
      patch postpone_lead_next_step_path(lead), params: { para: "escolher", em: "" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(lead.reload.next_step_on).to eq(now - 1.hour)
    end
  end

  it "grava o próximo passo com data e hora pelo formulário do lead" do
    lead = create(:lead)
    patch lead_path(lead), params: { lead: { next_step: "Agendar reunião", next_step_on: "2026-11-18T10:15" } }
    expect(lead.reload.next_step_on).to eq(Time.zone.local(2026, 11, 18, 10, 15))
    get edit_lead_path(lead)
    expect(response.body).to include('type="datetime-local"', "2026-11-18T10:15:00")
  end

  it "deixa o financeiro ver a lista, mas não concluir" do
    sign_in create(:user, :financeiro)
    lead = create(:lead, next_step_on: now)
    get next_steps_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(done_lead_next_step_path(lead))
    post done_lead_next_step_path(lead), params: { completion: { kind: "call", notes: "x", outcome: "lost", lost_reason: "Preço" } }
    expect(response).to have_http_status(:forbidden)
  end

  it "responde 403 para quem não acessa o Comercial" do
    sign_in create(:user, :suporte)
    get next_steps_path
    expect(response).to have_http_status(:forbidden)
  end
end
