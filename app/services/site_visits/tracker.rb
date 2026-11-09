# Recebe um evento do site (docs/specs/visitas-do-site, Coleta) e grava a visita, a página vista ou
# o acesso de IA. Chamado pelo Webhooks::SiteVisitsController, com o JSON que o PHP do site repassa.
#
#   SiteVisits::Tracker.new(payload).track  # => :pageview, :leave, :ai_hit ou :ignored
#
# Tipos: pageview e leave vêm do script do site (pessoas, com JavaScript); server_hit vem da captura
# no servidor, que só recebe quem tem cara de robô ou agente, e só vira acesso de IA. O beacon de um
# agente de IA é ignorado: o acesso dele já veio pelo server_hit.
#
# O IP só entra no hash do visitante e na conferência das faixas dos robôs. Não é gravado.
module SiteVisits
  class Tracker
    class Invalid < StandardError; end

    TYPES = %w[pageview leave server_hit].freeze
    UTM = %w[utm_source utm_medium utm_campaign utm_content utm_term].freeze
    PATH_LIMIT = 500
    UTM_LIMIT = 200

    def self.hosts = Rails.configuration.x.site_visits.hosts

    def initialize(payload)
      @payload = payload.to_h.stringify_keys
      @headers = @payload["headers"].is_a?(Hash) ? @payload["headers"].transform_keys { |k| k.to_s.downcase } : {}
      @now = Time.current
    end

    def track
      validate!
      return :ignored unless self.class.hosts.include?(@uri.host.to_s.downcase)

      agent = AiAgentClassifier.new(@headers, ip).classify
      return record_ai_hit(agent) if agent && type == "server_hit"
      return :ignored if agent || type == "server_hit" || robot?

      type == "pageview" ? record_pageview : record_leave
    end

    private

    def type = @payload["type"].to_s
    def client_id = @payload["id"].to_s
    def ip = @payload["ip"].to_s
    def user_agent = @headers["user-agent"].to_s

    def validate!
      raise Invalid, "type desconhecido" unless TYPES.include?(type)
      raise Invalid, "ip ausente" if ip.blank?
      raise Invalid, "id ausente ou inválido" if type != "server_hit" && !client_id.match?(/\A[\w-]{8,64}\z/)

      @uri = URI(@payload["url"].to_s)
      raise Invalid, "url ausente ou inválida" unless @uri.is_a?(URI::HTTP) && @uri.host.present?
    rescue URI::InvalidURIError
      raise Invalid, "url ausente ou inválida"
    end

    # Robô que não é de IA, e o prefetch/prerender do navegador.
    def robot?
      UserAgent.new(user_agent).bot? || [ @headers["sec-purpose"], @headers["purpose"] ].join.include?("prefetch")
    end

    def record_ai_hit(agent)
      AiHit.create!(agent.to_h.merge(path: path, occurred_at: @now))
      :ai_hit
    end

    def record_pageview
      SiteVisit.transaction do
        # Dois envios ao mesmo tempo do mesmo visitante não abrem duas visitas.
        SiteVisit.connection.execute(SiteVisit.sanitize_sql([ "SELECT pg_advisory_xact_lock(hashtext(?))", visitor_hash ]))
        unless SitePageview.exists?(client_id: client_id)
          visit = SiteVisit.open_for(visitor_hash, @now)
          if visit
            visit.update!(last_seen_at: @now, exit_path: path, pageviews_count: visit.pageviews_count + 1)
          else
            visit = SiteVisit.create!(new_visit_attributes)
          end
          visit.pageviews.create!(client_id: client_id, path: path, occurred_at: @now)
        end
      end
      :pageview
    rescue ActiveRecord::RecordNotUnique
      :pageview
    end

    # Só o primeiro leave de cada página conta. A duração da visita é a soma do tempo visível das páginas.
    def record_leave
      seconds = (@payload["duration_ms"].to_f / 1000).round.clamp(0, SitePageview::MAX_DURATION)
      pageview = SitePageview.find_by(client_id: client_id)
      return :ignored unless pageview && SitePageview.where(id: pageview.id, duration_seconds: nil).update_all(duration_seconds: seconds, updated_at: @now) == 1

      visit = pageview.site_visit
      visit.update!(duration_seconds: visit.pageviews.sum(:duration_seconds))
      :leave
    end

    def new_visit_attributes
      utm = self.utm
      channel, assistant = Channel.new(referrer_host: referrer_host, **utm.slice("utm_source", "utm_medium", "utm_campaign").symbolize_keys).classify
      agent = UserAgent.new(user_agent, screen_width: @payload["screen_width"])
      { visitor_hash: visitor_hash, started_at: @now, last_seen_at: @now, pageviews_count: 1, entry_path: path, exit_path: path,
        referrer_host: referrer_host, channel: channel, ai_assistant: assistant,
        device_type: agent.device_type, browser: agent.browser, os: agent.os, **utm }
    end

    def visitor_hash
      @visitor_hash ||= Digest::SHA256.hexdigest([ SiteVisitSalt.for(@now.to_date), ip, user_agent ].join("|")).first(16)
    end

    # Só o caminho, sem a query (que pode trazer e-mail ou token) e sem barra no fim.
    def path
      @path ||= begin
        value = @uri.path.presence || "/"
        value = value.chomp("/") while value.length > 1 && value.end_with?("/")
        value.first(PATH_LIMIT)
      end
    end

    def utm
      query = Rack::Utils.parse_query(@uri.query.to_s)
      UTM.index_with { |key| Array(query[key]).first.to_s.strip.first(UTM_LIMIT).presence }.compact
    end

    # Host da referência, sem www. A do próprio site conta como vazia (navegação interna ou direta).
    def referrer_host
      return @referrer_host if defined?(@referrer_host)

      host = URI(@payload["referrer"].to_s).host.to_s.downcase.delete_prefix("www.")
      @referrer_host = host.presence unless self.class.hosts.map { |h| h.delete_prefix("www.") }.include?(host)
    rescue URI::InvalidURIError
      @referrer_host = nil
    end
  end
end
