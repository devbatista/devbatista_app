# Canal de origem de uma visita, pela referência, pela UTM, pelo ID de clique da URL e pelo navegador
# interno de app (docs/specs/visitas-do-site, Canal). Vale a primeira regra que bater: Assistentes de
# IA, E-mail, Campanha, Busca, Redes sociais, Outros sites, Direto.
#
#   SiteVisits::Channel.new(referrer_host: "chatgpt.com").classify  # => ["ai_assistant", "ChatGPT"]
module SiteVisits
  class Channel
    SEARCH = /\A(google\.[a-z.]+|bing\.com|duckduckgo\.com|([a-z]+\.)?search\.yahoo\.com|yahoo\.com|ecosia\.org|yandex\.[a-z.]+|
              search\.brave\.com|com\.google\.android\.googlequicksearchbox)\z/x
    # Redes e mensageiros. wl.co é o redirecionador dos links do WhatsApp (l.wl.co); os com.* e org.*
    # são a referência android-app:// dos apps no Android.
    SOCIAL = %w[instagram.com facebook.com messenger.com linkedin.com lnkd.in t.co x.com twitter.com youtube.com
                tiktok.com threads.net threads.com bsky.app pinterest.com reddit.com snapchat.com
                whatsapp.com wa.me wl.co t.me telegram.org discord.com slack.com teams.microsoft.com teams.live.com
                com.linkedin.android com.whatsapp com.instagram.android com.facebook.katana com.facebook.orca
                com.twitter.android com.zhiliaoapp.musically org.telegram.messenger com.slack com.discord].freeze
    WEBMAIL = %w[mail.google.com outlook.live.com outlook.office.com outlook.office365.com mail.yahoo.com
                 com.google.android.gm].freeze
    EMAIL_MEDIUMS = %w[email e-mail newsletter].freeze
    # IDs de clique que só existem em anúncio. O fbclid fica de fora: a Meta o põe em todo link que sai
    # do Facebook e do Instagram, pago ou não.
    PAID_CLICKS = %w[google_ads microsoft_ads tiktok linkedin x].freeze

    def self.assistants = AiAgentClassifier.catalog.fetch("assistants")

    # click_source: a plataforma do ID de clique (SiteVisit::CLICK_SOURCE_LABELS). in_app: o app em cujo
    # navegador interno a página abriu (SiteVisits::UserAgent#in_app).
    def initialize(referrer_host: nil, utm_source: nil, utm_medium: nil, utm_campaign: nil, click_source: nil, in_app: nil)
      @referrer = referrer_host.presence
      @source = utm_source.to_s.downcase.presence
      @medium = utm_medium.to_s.downcase.presence
      @campaign = utm_campaign.presence
      @click = click_source.presence
      @in_app = in_app.presence
    end

    # [canal, assistente de IA ou nil]
    def classify
      assistant = assistant_for(@referrer) || assistant_for(@source)
      return [ "ai_assistant", assistant ] if assistant
      return [ "email", nil ] if EMAIL_MEDIUMS.include?(@medium) || matches?(@referrer, WEBMAIL)
      return [ "campaign", nil ] if @source || @medium || @campaign || PAID_CLICKS.include?(@click)
      # Sem referência, o fbclid ou o navegador interno do app ainda dizem que veio de rede social.
      return [ @in_app || @click == "meta" ? "social" : "direct", nil ] unless @referrer
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
