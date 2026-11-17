require "rails_helper"

RSpec.describe "Webhook de visitas do site" do
  let(:pageview) do
    { type: "pageview", id: "3f1c2b4a-0000-4000-8000-000000000001", url: "https://www.devbatista.com/solucoes?utm_source=chatgpt.com",
      referrer: "", screen_width: 1440, ip: "200.1.2.3",
      headers: { "user-agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36" } }
  end

  def post_visit(body, token = "token-de-visitas-de-teste")
    post "/webhooks/site-visits", params: body.is_a?(String) ? body : JSON.generate(body),
                                  headers: { "Content-Type" => "application/json", "Authorization" => ("Bearer #{token}" if token) }.compact
  end

  it "grava a visita, sem login, e responde 202" do
    post_visit(pageview)

    expect(response).to have_http_status(:accepted)
    expect(SiteVisit.sole).to have_attributes(entry_path: "/solucoes", channel: "ai_assistant", ai_assistant: "ChatGPT", device_type: "desktop")
  end

  it "grava o acesso de IA vindo da captura no servidor" do
    post_visit(type: "server_hit", url: "https://www.devbatista.com/", ip: "1.2.3.4",
               headers: { "user-agent" => "Mozilla/5.0 (compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)" })

    expect(response).to have_http_status(:accepted)
    expect(AiHit.sole).to have_attributes(agent: "perplexitybot", kind: "search", path: "/")
  end

  it "responde 202 também quando descarta de propósito" do
    post_visit(pageview.merge(url: "https://outro-site.com/"))

    expect(response).to have_http_status(:accepted)
    expect(SiteVisit.count).to eq(0)
  end

  describe "teste automatizado" do
    def with_headers(extra) = pageview.merge(headers: pageview[:headers].merge(extra))

    it "descarta com 204 Origin ou Referer de outro host" do
      [ { "origin" => "http://localhost:4000" }, { "referer" => "https://evil.example/solucoes" },
        { "referer" => "https://devbatista.com.evil.example/" }, { "origin" => "null" } ].each do |extra|
        post_visit(with_headers(extra))
        expect(response).to have_http_status(:no_content)
      end
      expect(SiteVisit.count).to eq(0)
    end

    it "aceita Origin e Referer do site, com ou sem www, e a falta deles" do
      post_visit(with_headers("origin" => "https://devbatista.com", "referer" => "https://www.devbatista.com/solucoes"))
      expect(response).to have_http_status(:accepted)

      post_visit(with_headers("Referer" => "https://DevBatista.com/").merge(id: "3f1c2b4a-0000-4000-8000-000000000002"))
      expect(response).to have_http_status(:accepted)

      post_visit(with_headers("origin" => "", "referer" => "").merge(id: "3f1c2b4a-0000-4000-8000-000000000003"))
      expect(response).to have_http_status(:accepted)
      expect(SitePageview.count).to eq(3)
    end

    it "descarta com 204 user agent de navegador automatizado" do
      [ "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/142.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh) Chrome/142.0.0.0 Safari/537.36 Playwright/1.56.0",
        "Mozilla/5.0 Puppeteer", "Mozilla/5.0 (Windows NT 10.0) Selenium/4.25 Chrome/142.0.0.0" ].each do |ua|
        post_visit(with_headers("user-agent" => ua))
        expect(response).to have_http_status(:no_content)
      end
      expect(SiteVisit.count).to eq(0)
    end

    it "descarta com 204 a flag webdriver" do
      post_visit(pageview.merge(webdriver: true))
      expect(response).to have_http_status(:no_content)

      post_visit(pageview.merge(webdriver: false))
      expect(response).to have_http_status(:accepted)
      expect(SiteVisit.count).to eq(1)
    end

    it "descarta o leave de teste automatizado sem gravar o tempo" do
      post_visit(pageview)
      post_visit(type: "leave", id: pageview[:id], duration_ms: 30_000, ip: "200.1.2.3",
                 headers: pageview[:headers].merge("user-agent" => "Mozilla/5.0 HeadlessChrome/142.0.0.0"))

      expect(response).to have_http_status(:no_content)
      expect(SitePageview.sole.duration_seconds).to be_nil
    end

    it "não aplica o filtro ao server_hit, cujo Referer é a referência de verdade" do
      post_visit(type: "server_hit", url: "https://www.devbatista.com/", ip: "1.2.3.4",
                 headers: { "user-agent" => "Mozilla/5.0 (compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)",
                            "referer" => "https://www.perplexity.ai/" })

      expect(response).to have_http_status(:accepted)
      expect(AiHit.count).to eq(1)
    end

    it "valida o corpo antes de descartar" do
      post_visit(pageview.merge(type: "click", webdriver: true))
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "recusa token errado, ausente ou não configurado" do
    post_visit(pageview, "errado")
    expect(response).to have_http_status(:unauthorized)

    post_visit(pageview, "token-do-site-de-teste")
    expect(response).to have_http_status(:unauthorized)

    post_visit(pageview, nil)
    expect(response).to have_http_status(:unauthorized)

    allow(Rails.configuration.x.site_visits).to receive(:token).and_return(nil)
    post_visit(pageview)
    expect(response).to have_http_status(:unauthorized)
    expect(SiteVisit.count).to eq(0)
  end

  it "recusa JSON inválido, corpo que não é objeto, dados inválidos e corpo grande demais" do
    post_visit("{nao é json")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq("errors" => [ "JSON inválido" ])

    post_visit("[1, 2]")
    expect(response.parsed_body).to eq("errors" => [ "o corpo precisa ser um objeto JSON" ])

    post_visit(pageview.merge(type: "click"))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq("errors" => [ "type desconhecido" ])

    post_visit(pageview.merge(referrer: "x" * 17.kilobytes))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(SiteVisit.count).to eq(0)
  end
end
