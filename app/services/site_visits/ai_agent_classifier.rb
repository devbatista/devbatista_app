# Diz, pelos headers da requisição, se quem buscou a página é um robô ou agente de IA
# (docs/specs/visitas-do-site, Acessos de IA). O catálogo fica em config/ai_agents.yml.
#
#   SiteVisits::AiAgentClassifier.new(headers, ip).classify
#   # => #<data Result agent="chatgpt-user", agent_name="ChatGPT-User", company="OpenAI", kind="user",
#   #          verification="ip_verified", signature_agent=nil, accepts_markdown=false>  (ou nil)
#
# Verificação: user agent do catálogo com IP fora das faixas oficiais é falso, mesmo assinado (a
# assinatura ainda não é conferida). Dentro das faixas, IP confirmado. Senão, assinado se veio com
# Signature-Agent, ou declarado. Só o Signature-Agent, sem user agent do catálogo, é navegação autônoma.
module SiteVisits
  class AiAgentClassifier
    Result = Data.define(:agent, :agent_name, :company, :kind, :verification, :signature_agent, :accepts_markdown)

    def self.catalog
      @catalog ||= YAML.load_file(Rails.root.join("config/ai_agents.yml")).freeze
    end

    def self.patterns
      @patterns ||= catalog.fetch("agents").to_h do |key, agent|
        [ key, /(?<![\w-])#{Regexp.escape(agent.fetch("pattern"))}(?![\w-])/i ]
      end
    end

    # headers: nomes em minúsculas (como o PHP do site manda).
    def initialize(headers, ip)
      @headers = headers.to_h.transform_keys { |name| name.to_s.downcase }
      @ip = ip
    end

    def classify
      user_agent = @headers["user-agent"].to_s
      key = self.class.patterns.find { |_, pattern| user_agent.match?(pattern) }&.first
      return declared_agent(key) if key
      return signed_agent if signature_host

      nil
    end

    private

    def declared_agent(key)
      agent = self.class.catalog.fetch("agents").fetch(key)
      in_ranges = agent["ip_ranges_url"].present? ? AiAgentIpRanges.include?(key, @ip) : nil
      verification =
        if in_ranges == false then "spoofed"
        elsif in_ranges then "ip_verified"
        elsif signature_host then "signed"
        else "declared"
        end
      result(key, agent["name"], agent["company"], agent["kind"], verification)
    end

    def signed_agent
      known = self.class.catalog.fetch("signature_agents")[signature_host] || {}
      result("signed:#{signature_host}", known["name"] || signature_host, known["company"] || signature_host, "agent", "signed")
    end

    def result(agent, name, company, kind, verification)
      Result.new(agent: agent, agent_name: name, company: company, kind: kind, verification: verification,
                 signature_agent: signature_host, accepts_markdown: @headers["accept"].to_s.include?("text/markdown"))
    end

    # Signature-Agent é um structured field com a URL entre aspas. As versões do rascunho do Web Bot
    # Auth variam entre o valor solto ("https://chatgpt.com") e o dicionário (sig1="https://chatgpt.com").
    def signature_host
      return @signature_host if defined?(@signature_host)

      raw = @headers["signature-agent"].to_s.strip
      value = (raw[/"([^"]*)"/, 1] || raw).strip
      @signature_host = value.presence && (URI(value).host || value).downcase.delete_prefix("www.").first(100)
    rescue URI::InvalidURIError
      @signature_host = value.downcase.first(100)
    end
  end
end
