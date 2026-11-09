require "rails_helper"

RSpec.describe "Classificação das visitas do site" do
  describe SiteVisits::Channel do
    def channel(**attributes) = described_class.new(**attributes).classify

    it "segue a ordem das regras: IA, e-mail, campanha, busca, redes, outros sites, direto" do
      expect(channel(referrer_host: "chatgpt.com")).to eq([ "ai_assistant", "ChatGPT" ])
      expect(channel(referrer_host: "www.perplexity.ai")).to eq([ "ai_assistant", "Perplexity" ])
      expect(channel(utm_source: "chatgpt.com", utm_medium: "referral")).to eq([ "ai_assistant", "ChatGPT" ])
      expect(channel(utm_source: "mailchimp", utm_medium: "Email")).to eq([ "email", nil ])
      expect(channel(referrer_host: "mail.google.com")).to eq([ "email", nil ])
      expect(channel(referrer_host: "google.com", utm_campaign: "black-friday")).to eq([ "campaign", nil ])
      expect(channel(referrer_host: "google.com.br")).to eq([ "search", nil ])
      expect(channel(referrer_host: "duckduckgo.com")).to eq([ "search", nil ])
      expect(channel(referrer_host: "l.instagram.com")).to eq([ "social", nil ])
      expect(channel(referrer_host: "t.co")).to eq([ "social", nil ])
      expect(channel(referrer_host: "blog.exemplo.com.br")).to eq([ "referral", nil ])
      expect(channel).to eq([ "direct", nil ])
    end

    it "não confunde domínio parecido com assistente ou rede" do
      expect(channel(referrer_host: "notchatgpt.com")).to eq([ "referral", nil ])
      expect(channel(referrer_host: "fakeinstagram.com")).to eq([ "referral", nil ])
    end
  end

  describe SiteVisits::UserAgent do
    it "lê dispositivo, navegador e sistema" do
      iphone = described_class.new("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
      expect([ iphone.device_type, iphone.browser, iphone.os ]).to eq(%w[mobile Safari iOS])

      edge = described_class.new("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0")
      expect([ edge.device_type, edge.browser, edge.os ]).to eq(%w[desktop Edge Windows])

      instagram = described_class.new("Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Mobile Safari/537.36 Instagram 350.0", screen_width: 412)
      expect([ instagram.device_type, instagram.browser, instagram.os ]).to eq(%w[mobile Instagram Android])
    end

    it "prefere a largura da tela ao user agent" do
      expect(described_class.new("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)").device_type).to eq("tablet")
      expect(described_class.new("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)", screen_width: 1366).device_type).to eq("desktop")
      expect(described_class.new("Mozilla/5.0 (Macintosh)", screen_width: 900).device_type).to eq("tablet")
    end

    it "reconhece robôs sem pegar celular Cubot" do
      expect(described_class.new("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)")).to be_bot
      expect(described_class.new("Mozilla/5.0 (X11; Linux x86_64) HeadlessChrome/142.0")).to be_bot
      expect(described_class.new("curl/8.7.1")).to be_bot
      expect(described_class.new("")).to be_bot
      expect(described_class.new("Mozilla/5.0 (Linux; Android 10; CUBOT X30) AppleWebKit/537.36 Chrome/141.0 Mobile Safari/537.36")).not_to be_bot
    end
  end

  describe SiteVisits::AiAgentClassifier do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    def classify(ua, ip: "52.230.152.10", **headers)
      described_class.new({ "User-Agent" => ua, **headers.transform_keys { |k| k.to_s.tr("_", "-") } }, ip).classify
    end

    let(:chatgpt_user) { "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ChatGPT-User/1.0; +https://openai.com/bot)" }

    it "confere o IP nas faixas oficiais: dentro é confirmado, fora é falso" do
      cache.write(SiteVisits::AiAgentIpRanges.cache_key("chatgpt-user"), [ "52.230.152.0/24", "2603:1000::/25" ])

      expect(classify(chatgpt_user).to_h).to eq(agent: "chatgpt-user", agent_name: "ChatGPT-User", company: "OpenAI", kind: "user",
                                                 verification: "ip_verified", signature_agent: nil, accepts_markdown: false)
      expect(classify(chatgpt_user, ip: "2603:1000::1").verification).to eq("ip_verified")
      expect(classify(chatgpt_user, ip: "8.8.8.8").verification).to eq("spoofed")
      expect(classify(chatgpt_user, ip: "8.8.8.8", signature_agent: '"https://chatgpt.com"').verification).to eq("spoofed")
    end

    it "sem faixas no cache, fica declarado e pede a atualização uma vez por hora" do
      expect { 2.times { expect(classify(chatgpt_user).verification).to eq("declared") } }
        .to have_enqueued_job(AiAgentIpRangesJob).exactly(:once)
    end

    it "registra o acesso mesmo quando não consegue enfileirar a atualização" do
      allow(AiAgentIpRangesJob).to receive(:perform_later).and_raise(RedisClient::CannotConnectError, "sem Redis")
      expect(classify(chatgpt_user).verification).to eq("declared")
    end

    it "agente sem faixas publicadas fica declarado, ou assinado com Signature-Agent" do
      expect(classify("Claude-User (claude-code/2.1; +https://support.anthropic.com/)").to_h)
        .to include(agent: "claude-user", company: "Anthropic", kind: "user", verification: "declared")
      expect(classify("Mozilla/5.0 (compatible; Claude-SearchBot/1.0)").agent).to eq("claude-searchbot")
      expect(classify("Mozilla/5.0 (compatible; ClaudeBot/1.0; +claudebot@anthropic.com)", signature_agent: '"https://claude.ai"').verification).to eq("signed")
    end

    it "só a assinatura, com user agent de navegador, é navegação autônoma" do
      chrome = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"

      expect(classify(chrome, signature_agent: 'sig1="https://chatgpt.com"').to_h)
        .to eq(agent: "signed:chatgpt.com", agent_name: "ChatGPT agent", company: "OpenAI", kind: "agent",
               verification: "signed", signature_agent: "chatgpt.com", accepts_markdown: false)
      expect(classify(chrome, signature_agent: '"https://agente.exemplo.com"').to_h)
        .to include(agent: "signed:agente.exemplo.com", agent_name: "agente.exemplo.com", company: "agente.exemplo.com")
      expect(classify(chrome)).to be_nil
      expect(classify("Mozilla/5.0 (compatible; Googlebot/2.1)")).to be_nil
    end

    it "marca quem pede Markdown" do
      expect(classify("Mozilla/5.0 (compatible; GPTBot/1.2; +https://openai.com/gptbot)", accept: "text/markdown;q=1, text/html;q=0.8").accepts_markdown).to be(true)
    end
  end

  describe SiteVisits::AiAgentIpRanges do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    def http_response(code, body)
      klass = code == 200 ? Net::HTTPOK : Net::HTTPNotFound
      klass.new("1.1", code.to_s, "").tap { |response| allow(response).to receive(:body).and_return(body) }
    end

    it "baixa as faixas IPv4 e IPv6 do JSON oficial" do
      allow(Net::HTTP).to receive(:start).and_return(http_response(200, '{"prefixes":[{"ipv4Prefix":"1.2.3.0/24"},{"ipv6Prefix":"2603:1000::/25"}]}'))
      expect(described_class.fetch("https://openai.com/gptbot.json")).to eq([ "1.2.3.0/24", "2603:1000::/25" ])
    end

    it "recusa resposta de erro, JSON vazio ou faixa inválida" do
      allow(Net::HTTP).to receive(:start).and_return(http_response(404, ""))
      expect { described_class.fetch("https://openai.com/gptbot.json") }.to raise_error(described_class::Error, "HTTP 404")

      allow(Net::HTTP).to receive(:start).and_return(http_response(200, '{"prefixes":[]}'))
      expect { described_class.fetch("https://openai.com/gptbot.json") }.to raise_error(described_class::Error, "nenhuma faixa no JSON")

      allow(Net::HTTP).to receive(:start).and_return(http_response(200, '{"prefixes":[{"ipv4Prefix":"não é IP"}]}'))
      expect { described_class.fetch("https://openai.com/gptbot.json") }.to raise_error(described_class::Error)
    end

    it "atualiza os agentes que publicam faixas e mantém as anteriores quando o download falha" do
      cache.write(described_class.cache_key("gptbot"), [ "9.9.9.0/24" ])
      allow(described_class).to receive(:fetch) do |url|
        raise described_class::Error, "HTTP 500" if url.include?("gptbot")

        [ "1.2.3.0/24" ]
      end

      described_class.refresh_all

      expect(cache.read(described_class.cache_key("gptbot"))).to eq([ "9.9.9.0/24" ])
      expect(cache.read(described_class.cache_key("chatgpt-user"))).to eq([ "1.2.3.0/24" ])
      expect(cache.read(described_class.cache_key("claudebot"))).to be_nil
      expect(described_class).to have_received(:fetch).exactly(5).times
    end
  end
end
