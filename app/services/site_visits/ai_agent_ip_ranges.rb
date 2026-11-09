# Faixas de IP oficiais dos robôs de IA que as publicam (ip_ranges_url em config/ai_agents.yml),
# guardadas no cache. O AiAgentIpRangesJob atualiza uma vez por dia; se o download falhar, as
# faixas anteriores continuam valendo. Sem faixas no cache, o acesso não é conferido (fica
# "declarado") e a atualização é pedida, no máximo uma vez por hora.
module SiteVisits
  class AiAgentIpRanges
    class Error < StandardError; end

    TIMEOUT = 10

    def self.cache_key(agent) = "site_visits/ai_agent_ip_ranges/#{agent}"

    # true/false quando há faixas do agente; nil quando não há o que conferir.
    def self.include?(agent, ip)
      ranges = Rails.cache.read(cache_key(agent))
      if ranges.nil?
        request_refresh
        return nil
      end

      address = IPAddr.new(ip.to_s)
      ranges.any? { |range| IPAddr.new(range).include?(address) }
    rescue IPAddr::Error
      false
    end

    # Falha ao enfileirar (Redis fora do ar) não derruba o registro do acesso.
    def self.request_refresh
      return unless Rails.cache.write("site_visits/ai_agent_ip_ranges/refresh", true, unless_exist: true, expires_in: 1.hour)

      AiAgentIpRangesJob.perform_later
    rescue StandardError => e
      Rails.logger.warn("[SiteVisits] atualização das faixas de IP não enfileirada: #{e.message}")
    end

    # Baixa as faixas de todos os agentes do catálogo que as publicam.
    def self.refresh_all
      AiAgentClassifier.catalog.fetch("agents").each do |key, agent|
        next if agent["ip_ranges_url"].blank?

        Rails.cache.write(cache_key(key), fetch(agent["ip_ranges_url"]))
      rescue Error => e
        Rails.logger.warn("[SiteVisits] faixas de IP de #{key} não atualizadas: #{e.message}")
      end
    end

    def self.fetch(url)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => "AdminDevBatista/1.0"))
      end
      raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      prefixes = Array(JSON.parse(response.body)["prefixes"]).filter_map { |p| p["ipv4Prefix"] || p["ipv6Prefix"] }
      raise Error, "nenhuma faixa no JSON" if prefixes.empty?

      prefixes.each { |prefix| IPAddr.new(prefix) }
      prefixes
    rescue JSON::ParserError, IPAddr::Error, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Error, e.message
    end
  end
end
