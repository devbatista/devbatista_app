# Canal de origem de uma visita, pela referência e pela UTM (docs/specs/visitas-do-site, Canal).
# Vale a primeira regra que bater: Assistentes de IA, E-mail, Campanha, Busca, Redes sociais,
# Outros sites, Direto.
#
#   SiteVisits::Channel.new(referrer_host: "chatgpt.com").classify  # => ["ai_assistant", "ChatGPT"]
module SiteVisits
  class Channel
    SEARCH = /\A(google\.[a-z.]+|bing\.com|duckduckgo\.com|(search\.)?yahoo\.com|ecosia\.org|yandex\.[a-z.]+|
              search\.brave\.com|com\.google\.android\.googlequicksearchbox)\z/x
    SOCIAL = %w[instagram.com facebook.com linkedin.com lnkd.in t.co x.com twitter.com youtube.com tiktok.com
                threads.net whatsapp.com wa.me pinterest.com reddit.com com.linkedin.android].freeze
    WEBMAIL = %w[mail.google.com outlook.live.com outlook.office.com outlook.office365.com mail.yahoo.com
                 com.google.android.gm].freeze
    EMAIL_MEDIUMS = %w[email e-mail newsletter].freeze

    def self.assistants = AiAgentClassifier.catalog.fetch("assistants")

    def initialize(referrer_host: nil, utm_source: nil, utm_medium: nil, utm_campaign: nil)
      @referrer = referrer_host.presence
      @source = utm_source.to_s.downcase.presence
      @medium = utm_medium.to_s.downcase.presence
      @campaign = utm_campaign.presence
    end

    # [canal, assistente de IA ou nil]
    def classify
      assistant = assistant_for(@referrer) || assistant_for(@source)
      return [ "ai_assistant", assistant ] if assistant
      return [ "email", nil ] if EMAIL_MEDIUMS.include?(@medium) || matches?(@referrer, WEBMAIL)
      return [ "campaign", nil ] if @source || @medium || @campaign
      return [ "direct", nil ] unless @referrer
      return [ "search", nil ] if @referrer.match?(SEARCH)
      return [ "social", nil ] if matches?(@referrer, SOCIAL)

      [ "referral", nil ]
    end

    private

    def assistant_for(host)
      return unless host

      self.class.assistants.find { |domain, _| host == domain || host.end_with?(".#{domain}") }&.last
    end

    # O host ou um subdomínio dele (l.instagram.com, m.facebook.com).
    def matches?(host, list)
      host && list.any? { |domain| host == domain || host.end_with?(".#{domain}") }
    end
  end
end
