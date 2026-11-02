require "net/http"

module Billing
  # Histórico de cobranças da conta na Cloudflare (GET /accounts/:id/billing/history).
  #
  # Credencial: um API token com a permissão "Billing: Read" da conta, na variável
  # BILLING_CLOUDFLARE_API_TOKEN. A conta (Account ID) vem da conexão.
  #
  # Cada item com valor positivo dos últimos 6 meses vira uma despesa, vencendo na data da
  # cobrança. Está paga quando amount_to_pay é zero (ou, sem esse campo, quando o status diz
  # pago ou há recibo). Estornos e créditos ficam de fora.
  class Cloudflare
    ENDPOINT = "https://api.cloudflare.com/client/v4/accounts/%s/billing/history".freeze
    PER_PAGE = 50
    MAX_PAGES = 4
    MONTHS_BACK = 6
    TIMEOUT = 10
    PAID_STATUSES = %w[paid success succeeded settled].freeze

    def initialize(connection, env: ENV)
      @connection = connection
      @env = env
    end

    def charges(today)
      since = (today << MONTHS_BACK).beginning_of_month
      items(since).filter_map { |item| charge(item, since) }
    end

    private

    def items(since)
      (1..MAX_PAGES).each_with_object([]) do |page, all|
        batch = get(page)
        all.concat(batch)
        break all if batch.size < PER_PAGE || batch.any? { |item| occurred_on(item).then { |d| d && d < since } }
      end
    end

    def charge(item, since)
      occurred = occurred_on(item)
      cents = Billing.to_cents(item["amount"] || 0)
      return if occurred.nil? || occurred < since || !cents.positive?
      return if "#{item['type']} #{item['action']}".match?(/refund|credit/i)

      paid = paid?(item)
      Charge.new(external_id: item["id"].to_s, competence: occurred.beginning_of_month, due_on: occurred,
                 description: "Cloudflare — #{item['description'].presence || 'cobrança'}",
                 currency: item["currency"].to_s.upcase.presence || "USD", amount_cents: cents,
                 status: paid ? :paid : :pending, paid_on: (occurred if paid))
    end

    def paid?(item)
      return BigDecimal(item["amount_to_pay"].to_s).zero? unless item["amount_to_pay"].nil?

      PAID_STATUSES.include?(item["status"].to_s.downcase) || item["receipt_id"].present?
    end

    def occurred_on(item)
      Time.zone.parse(item["occurred_at"].to_s)&.to_date
    rescue ArgumentError
      nil
    end

    def get(page)
      uri = URI(format(ENDPOINT, @connection.account_id))
      uri.query = URI.encode_www_form(page: page, per_page: PER_PAGE, order: "occurred_at", direction: "desc")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@env.fetch('BILLING_CLOUDFLARE_API_TOKEN')}"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end
      body = JSON.parse(response.body.presence || "{}")
      unless response.is_a?(Net::HTTPSuccess) && body["success"]
        reason = Array(body["errors"]).map { |e| e["message"] }.compact_blank.to_sentence.presence || "HTTP #{response.code}"
        raise Error, "Cloudflare respondeu: #{reason}"
      end
      Array(body["result"])
    rescue JSON::ParserError
      raise Error, "Cloudflare respondeu algo que não é JSON (HTTP #{response&.code})"
    end
  end
end
