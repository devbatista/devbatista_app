require "rails_helper"

RSpec.describe "Marketing → Visitas do site" do
  let(:admin) { create(:user, :admin) }
  let(:now) { Time.zone.local(2026, 11, 9, 14, 0) }

  around { |example| travel_to(now) { example.run } }

  it "mostra o passo a passo de instalação antes da primeira visita" do
    sign_in admin
    get site_visits_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nenhuma visita registrada ainda", "SITE_VISITS_TOKEN", "?nao-contar=1")
    expect(response.body).not_to include("Visitantes únicos")
  end

  it "mostra os seis indicadores com a comparação e o gráfico do período" do
    create_site_visit(at: now - 1.hour, pages: %w[/ /sobre], duration: 135)
    create_site_visit(at: now - 8.days, pages: %w[/])
    sign_in admin
    get site_visits_path

    expect(response.body).to include("Visitas do site", "Últimos 7 dias", "Visitantes únicos", "Páginas vistas", "Páginas por visita",
                                      "Taxa de rejeição", "Duração média", "2 min 15 s", "Visitas por dia", "anterior: 1",
                                      "09/11: 1 visita · 1 visitante · 2 páginas vistas", "Dados desde 01/11/2026", "visitas_por_dimensao")
    expect(response.body).to include(%(<option selected="selected" value="7d">))

    get site_visits_path(periodo: "hoje")
    expect(response.body).to include("Visitas por hora", "13h: 1 visita")
    expect(response.body).not_to include("cache de até 15 minutos")
  end

  it "fica no grupo Marketing do menu, só para quem tem a área" do
    sign_in admin
    get root_path
    expect(response.body).to include("Marketing", "Visitas do site", site_visits_path)

    comercial = create(:user, :comercial)
    sign_in comercial
    get root_path
    expect(response.body).not_to include(site_visits_path)
    get site_visits_path
    expect(response).to have_http_status(:forbidden)

    sign_in create(:user, role: create(:role, permissions: { "marketing" => "read", "dashboard" => "read" }))
    get site_visits_path
    expect(response).to have_http_status(:ok)
  end
end
