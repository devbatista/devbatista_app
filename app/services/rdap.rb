require "net/http"

# Consulta pública de domínios (RDAP, RFC 9083), sem autenticação. O servidor de cada TLD vem do
# bootstrap da IANA: .br → Registro.br, .com → Verisign (vale para domínios da GoDaddy também).
#
#   Rdap.expiration("devbatista.com") # => Date ou nil
#
# Em caso de falha devolve nil; quem chama decide o que fazer.
class Rdap
  BOOTSTRAP = "https://data.iana.org/rdap/dns.json".freeze
  TIMEOUT = 8

  class_attribute :enabled, default: !Rails.env.test?

  def self.expiration(name)
    return unless enabled

    base = server_for(name)
    return log_failure(name, "TLD sem servidor RDAP") unless base

    data = get_json(URI.join(base.end_with?("/") ? base : "#{base}/", "domain/#{name}"))
    event = Array(data&.fetch("events", nil)).find { |e| e["eventAction"] == "expiration" }
    event && Time.zone.parse(event["eventDate"].to_s)&.to_date
  rescue StandardError => e
    log_failure(name, e.message)
  end

  # Servidor do sufixo mais longo listado no bootstrap ("com.br" antes de "br").
  def self.server_for(name)
    services = Rails.cache.fetch("rdap/bootstrap", expires_in: 1.day, skip_nil: true) { get_json(URI(BOOTSTRAP))&.fetch("services", nil) }
    labels = name.to_s.downcase.split(".")
    (1...labels.size).each do |i|
      suffix = labels[i..].join(".")
      service = Array(services).find { |tlds, _urls| tlds.include?(suffix) }
      return service.last.find { |url| url.start_with?("https") } || service.last.first if service
    end
    nil
  end

  def self.get_json(uri, redirects = 3)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.get(uri.request_uri, "Accept" => "application/rdap+json, application/json")
    end
    return get_json(URI(response["location"]), redirects - 1) if response.is_a?(Net::HTTPRedirection) && redirects.positive?
    return unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def self.log_failure(name, reason)
    Rails.logger.warn("[Rdap] #{name}: #{reason}")
    nil
  end
end
