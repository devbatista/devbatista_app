# Visitas do site (docs/specs/visitas-do-site): 400 dias de visitas e acessos de IA inventados, para
# ver a tela e testar as tools do MCP. Só fora de produção e só se ainda não há visitas. Gerados com
# semente fixa: rodar de novo num banco limpo dá os mesmos números.
module Seeds
  module Visitas
    DAYS = 400

    PAGES = %w[/ /solucoes /tech-partner /para-agencias /produtos /projetos /sobre /contato /faq
               /sua-empresa-esta-perdendo-dinheiro-com-a-ti-sem-perceber].freeze

    # [canal, peso, referências possíveis, utm]
    CHANNELS = [
      [ "search", 34, %w[google.com google.com.br bing.com duckduckgo.com], nil ],
      [ "direct", 24, [ nil ], nil ],
      [ "social", 15, %w[l.instagram.com linkedin.com lm.facebook.com t.co], nil ],
      [ "ai_assistant", 8, %w[chatgpt.com perplexity.ai claude.ai gemini.google.com], nil ],
      [ "campaign", 9, [ nil ], { "utm_source" => "instagram", "utm_medium" => "paid", "utm_campaign" => "diagnostico-tecnologico" } ],
      [ "referral", 7, %w[github.com clutch.co blog.rdstation.com], nil ],
      [ "email", 3, [ nil ], { "utm_source" => "newsletter", "utm_medium" => "email", "utm_campaign" => "novidades" } ]
    ].freeze
    ASSISTANTS = { "chatgpt.com" => "ChatGPT", "perplexity.ai" => "Perplexity", "claude.ai" => "Claude", "gemini.google.com" => "Gemini" }.freeze

    DEVICES = [ [ "mobile", 58, 390, "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile Safari/604.1" ],
                [ "desktop", 38, 1440, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/142.0.0.0 Safari/537.36" ],
                [ "tablet", 4, 820, "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile Safari/604.1" ] ].freeze

    # [chave, nome, empresa, tipo, verificação, bloqueado, acessos por semana]
    AGENTS = [
      [ "gptbot", "GPTBot", "OpenAI", "training", "ip_verified", true, 9 ],
      [ "claudebot", "ClaudeBot", "Anthropic", "training", "declared", true, 6 ],
      [ "ccbot", "CCBot", "Common Crawl", "training", "declared", true, 3 ],
      [ "oai-searchbot", "OAI-SearchBot", "OpenAI", "search", "ip_verified", false, 5 ],
      [ "perplexitybot", "PerplexityBot", "Perplexity", "search", "ip_verified", false, 4 ],
      [ "chatgpt-user", "ChatGPT-User", "OpenAI", "user", "ip_verified", false, 7 ],
      [ "claude-user", "Claude-User", "Anthropic", "user", "declared", false, 3 ],
      [ "perplexity-user", "Perplexity-User", "Perplexity", "user", "ip_verified", false, 2 ],
      [ "gptbot", "GPTBot", "OpenAI", "training", "spoofed", true, 1 ]
    ].freeze

    def self.run
      return if SiteVisit.exists? || AiHit.exists?

      random = Random.new(42)
      visits = []
      pageviews = []
      today = Date.current
      (DAYS - 1).downto(0) do |ago|
        day = today - ago
        growth = 1 + (DAYS - ago) / DAYS.to_f # o tráfego dobra ao longo do período
        base = (day.saturday? || day.sunday? ? 9 : 18) * growth
        count = (base + random.rand(-4..6)).round.clamp(1, 80)
        hashes = Array.new((count * 0.85).ceil) { random.bytes(8).unpack1("H*") }
        count.times do
          started = day.in_time_zone.change(hour: weighted_hour(random), min: random.rand(60))
          next if started > Time.current

          visits << build_visit(random, started, hashes.sample(random: random), pageviews)
        end
      end
      SiteVisit.insert_all!(visits)
      SitePageview.insert_all!(pageviews)

      hits = []
      (DAYS - 1).downto(0) do |ago|
        AGENTS.each do |key, name, company, kind, verification, blocked, weekly|
          next unless random.rand < weekly / 7.0

          hits << { agent: key, agent_name: name, company: company, kind: kind, verification: verification, blocked: blocked,
                    path: PAGES.sample(random: random), accepts_markdown: kind == "user" && random.rand < 0.4,
                    occurred_at: (today - ago).in_time_zone.change(hour: random.rand(24), min: random.rand(60)) }
        end
      end
      AiHit.insert_all!(hits.reject { |hit| hit[:occurred_at] > Time.current }) if hits.any?
    end

    def self.build_visit(random, started, visitor_hash, pageviews)
      channel, _, referrers, utm = pick(random, CHANNELS)
      referrer = referrers.sample(random: random)
      device, _, width, user_agent = pick(random, DEVICES)
      agent = SiteVisits::UserAgent.new(user_agent, screen_width: width)
      count = [ 1, 1, 1, 2, 2, 3, 4, 5 ].sample(random: random)
      paths = [ entry_page(random, channel) ] + Array.new(count - 1) { PAGES.sample(random: random) }
      durations = count == 1 && random.rand < 0.6 ? [ random.rand(2..9) ] : Array.new(count) { random.rand(8..180) }
      id = SecureRandom.uuid
      at = started
      paths.each_with_index do |path, i|
        pageviews << { site_visit_id: id, client_id: SecureRandom.uuid, path: path, occurred_at: at, duration_seconds: durations[i] }
        at += durations[i].seconds + random.rand(1..20).seconds
      end
      { id: id, visitor_hash: visitor_hash, started_at: started, last_seen_at: pageviews.last[:occurred_at],
        pageviews_count: count, duration_seconds: durations.sum, entry_path: paths.first, exit_path: paths.last,
        referrer_host: referrer, channel: channel, ai_assistant: ASSISTANTS[referrer],
        device_type: device, browser: agent.browser, os: agent.os,
        **SiteVisits::Tracker::UTM.index_with(nil).merge(utm || {}).symbolize_keys }
    end

    # Campanha e e-mail caem na página do e-book; o resto, quase sempre na home.
    def self.entry_page(random, channel)
      return "/sua-empresa-esta-perdendo-dinheiro-com-a-ti-sem-perceber" if %w[campaign email].include?(channel)

      random.rand < 0.55 ? "/" : PAGES.sample(random: random)
    end

    # Mais visitas no horário comercial.
    def self.weighted_hour(random)
      random.rand < 0.75 ? random.rand(8..19) : random.rand(24)
    end

    def self.pick(random, table)
      roll = random.rand(table.sum { |row| row[1] })
      table.find { |row| (roll -= row[1]).negative? }
    end
  end
end

Seeds::Visitas.run
