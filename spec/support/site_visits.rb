# Visitas do site prontas para os testes dos números (SiteVisits::Stats, tela e tools do MCP).
module SiteVisitHelpers
  # Uma visita com as páginas dadas; cada página dura duration / pages.size segundos.
  def create_site_visit(at:, hash: SecureRandom.hex(8), pages: [ "/" ], duration: 60, channel: "direct", referrer: nil,
                        ai_assistant: nil, device: "desktop", **utm)
    visit = SiteVisit.create!(visitor_hash: hash, started_at: at, last_seen_at: at + duration.seconds, pageviews_count: pages.size,
                              duration_seconds: duration, entry_path: pages.first, exit_path: pages.last, channel: channel,
                              referrer_host: referrer, ai_assistant: ai_assistant, device_type: device, browser: "Chrome", os: "Windows", **utm)
    pages.each_with_index do |path, i|
      visit.pageviews.create!(client_id: SecureRandom.uuid, path: path, occurred_at: at + i.minutes, duration_seconds: duration / pages.size)
    end
    visit
  end

  def create_ai_hit(at:, agent: "chatgpt-user", name: "ChatGPT-User", company: "OpenAI", kind: "user", verification: "ip_verified",
                    blocked: false, path: "/")
    AiHit.create!(agent: agent, agent_name: name, company: company, kind: kind, verification: verification, blocked: blocked,
                  path: path, occurred_at: at)
  end
end

RSpec.configure do |config|
  config.include SiteVisitHelpers
end
