require "rails_helper"

RSpec.describe SiteVisits::Tracker do
  let(:iphone) { "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1" }
  let(:chrome) { "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36" }

  def track(type: "pageview", id: SecureRandom.uuid, url: "https://www.devbatista.com/", ip: "200.1.2.3", ua: iphone, headers: {}, **extra)
    described_class.new({ "type" => type, "id" => id, "url" => url, "ip" => ip,
                          "headers" => { "user-agent" => ua }.merge(headers), **extra.stringify_keys }).track
  end

  around { |example| travel_to(Time.zone.local(2026, 11, 9, 14, 0)) { example.run } }

  describe "pageview" do
    it "abre a visita com o canal, a UTM, o dispositivo e a página de entrada, sem guardar o IP" do
      expect(track(url: "https://www.devbatista.com/solucoes/?utm_source=instagram&utm_campaign=nov&email=ana@x.com",
                   referrer: "https://l.instagram.com/", screen_width: 390)).to eq(:pageview)

      visit = SiteVisit.sole
      expect(visit).to have_attributes(entry_path: "/solucoes", exit_path: "/solucoes", pageviews_count: 1, duration_seconds: 0,
                                       referrer_host: "l.instagram.com", utm_source: "instagram", utm_campaign: "nov", utm_medium: nil,
                                       channel: "campaign", device_type: "mobile", browser: "Safari", os: "iOS",
                                       started_at: Time.current, last_seen_at: Time.current)
      expect(visit.visitor_hash).to match(/\A\h{16}\z/)
      expect(visit.pageviews.sole).to have_attributes(path: "/solucoes", occurred_at: Time.current, duration_seconds: nil)
      stored = [ visit, visit.pageviews.sole ].flat_map { |record| record.attributes.values.map(&:to_s) }.join(" ")
      expect(stored).not_to include("200.1.2.3")
      expect(stored).not_to include("ana@x.com")
    end

    it "soma as páginas do mesmo visitante até 30 min sem atividade e depois abre outra visita" do
      track(url: "https://www.devbatista.com/")
      travel 20.minutes
      track(url: "https://www.devbatista.com/sobre")
      expect(SiteVisit.sole).to have_attributes(pageviews_count: 2, entry_path: "/", exit_path: "/sobre", last_seen_at: Time.current)

      travel 31.minutes
      track(url: "https://www.devbatista.com/contato")
      expect(SiteVisit.count).to eq(2)
      expect(SiteVisit.order(:started_at).last).to have_attributes(entry_path: "/contato", pageviews_count: 1)
    end

    it "separa visitantes pelo IP e pelo user agent, e o mesmo visitante vira outro no dia seguinte" do
      track
      track(ip: "200.1.2.4")
      track(ua: chrome)
      expect(SiteVisit.distinct.count(:visitor_hash)).to eq(3)

      travel_to(Time.zone.local(2026, 11, 10, 0, 5))
      track
      expect(SiteVisit.distinct.count(:visitor_hash)).to eq(4)
      expect(SiteVisitSalt.count).to eq(2)
    end

    it "ignora o mesmo id enviado de novo" do
      id = SecureRandom.uuid
      2.times { track(id: id) }
      expect(SiteVisit.sole.pageviews_count).to eq(1)
      expect(SitePageview.count).to eq(1)
    end

    it "classifica o canal pela referência e trata a referência do próprio site como direta" do
      track(referrer: "https://chatgpt.com/")
      track(ip: "1.1.1.1", referrer: "https://www.devbatista.com/sobre")
      track(ip: "1.1.1.2", referrer: "https://www.google.com.br/")

      expect(SiteVisit.pluck(:channel, :ai_assistant, :referrer_host))
        .to contain_exactly([ "ai_assistant", "ChatGPT", "chatgpt.com" ], [ "direct", nil, nil ], [ "search", nil, "google.com.br" ])
    end

    it "descarta robôs, o prefetch do navegador e páginas de outro host" do
      expect(track(ua: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)")).to eq(:ignored)
      expect(track(ua: "")).to eq(:ignored)
      expect(track(headers: { "sec-purpose" => "prefetch;prerender" })).to eq(:ignored)
      expect(track(url: "https://outro-site.com/")).to eq(:ignored)
      expect(SiteVisit.count).to eq(0)
    end

    it "não conta como pessoa o beacon de um agente de IA" do
      expect(track(ua: "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ChatGPT-User/1.0; +https://openai.com/bot)")).to eq(:ignored)
      expect(track(ua: chrome, headers: { "signature-agent" => '"https://chatgpt.com"' })).to eq(:ignored)
      expect(SiteVisit.count + AiHit.count).to eq(0)
    end
  end

  describe "leave" do
    it "grava o tempo visível da página, com teto de 30 min, e a duração da visita é a soma das páginas" do
      first = SecureRandom.uuid
      second = SecureRandom.uuid
      track(id: first)
      track(id: second, url: "https://www.devbatista.com/sobre")

      expect(track(type: "leave", id: first, duration_ms: 12_400)).to eq(:leave)
      expect(track(type: "leave", id: second, duration_ms: 3_600_000)).to eq(:leave)

      expect(SitePageview.find_by(client_id: first).duration_seconds).to eq(12)
      expect(SitePageview.find_by(client_id: second).duration_seconds).to eq(1800)
      expect(SiteVisit.sole.duration_seconds).to eq(1812)
    end

    it "só o primeiro leave de cada página conta, e leave sem pageview é ignorado" do
      id = SecureRandom.uuid
      track(id: id)
      track(type: "leave", id: id, duration_ms: 5_000)
      expect(track(type: "leave", id: id, duration_ms: 50_000)).to eq(:ignored)
      expect(SiteVisit.sole.duration_seconds).to eq(5)

      expect(track(type: "leave", id: SecureRandom.uuid, duration_ms: 5_000)).to eq(:ignored)
    end
  end

  describe "server_hit" do
    it "grava o acesso de IA com o caminho, sem query, e ignora navegador comum e outros robôs" do
      expect(track(type: "server_hit", id: nil, url: "https://www.devbatista.com/tech-partner?x=1",
                   ua: "Mozilla/5.0 (compatible; ClaudeBot/1.0; +claudebot@anthropic.com)", headers: { "accept" => "text/markdown, text/html" })).to eq(:ai_hit)
      expect(AiHit.sole).to have_attributes(agent: "claudebot", agent_name: "ClaudeBot", company: "Anthropic", kind: "training",
                                            verification: "declared", path: "/tech-partner", accepts_markdown: true, occurred_at: Time.current)

      expect(track(type: "server_hit", id: nil, ua: chrome)).to eq(:ignored)
      expect(track(type: "server_hit", id: nil, ua: "Mozilla/5.0 (compatible; bingbot/2.0)")).to eq(:ignored)
      expect(AiHit.count).to eq(1)
      expect(SiteVisit.count).to eq(0)
    end
  end

  describe "validação" do
    it "recusa tipo desconhecido, IP ausente, id inválido e URL inválida" do
      expect { track(type: "click") }.to raise_error(described_class::Invalid, "type desconhecido")
      expect { track(ip: "") }.to raise_error(described_class::Invalid, "ip ausente")
      expect { track(id: "x") }.to raise_error(described_class::Invalid, "id ausente ou inválido")
      expect { track(url: "javascript:alert(1)") }.to raise_error(described_class::Invalid, "url ausente ou inválida")
      expect { track(url: "nao é url") }.to raise_error(described_class::Invalid, "url ausente ou inválida")
    end
  end
end
