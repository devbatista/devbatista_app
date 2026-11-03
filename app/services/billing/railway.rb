require "net/http"

module Billing
  # Faturas do Railway pela API GraphQL pública (workspace → customer → invoices) e estimativa
  # do ciclo corrente (currentUsage). As consultas de faturamento não estão na documentação do
  # Railway, só no schema da API: se mudarem, a sincronização falha com a mensagem da API.
  #
  # Credencial: um token de workspace (Account Settings → Tokens) na variável
  # BILLING_RAILWAY_API_TOKEN. A conta é o ID do workspace (railway usage --json).
  #
  # - O ciclo vai do dia da assinatura ao mesmo dia do mês seguinte (18/10 a 18/11), não do dia 1º.
  #   A competência é o mês em que o ciclo começa.
  # - Fatura (Stripe: total em centavos de dólar, período = consumo cobrado) → despesa vencendo no
  #   fim do ciclo, paga quando o status é "paid". Rascunho, anulada e valor zero ficam de fora.
  #   Fatura reemitida substitui a original.
  # - Consumo do ciclo corrente → despesa Prevista ("estimate:2026-10-18"), cancelada quando a
  #   fatura do ciclo fecha.
  class Railway
    ENDPOINT = "https://backboard.railway.com/graphql/v2".freeze
    TIMEOUT = 10
    IGNORED_STATUSES = %w[draft void].freeze
    QUERY = <<~GRAPHQL.freeze
      query($id: String!) {
        workspace(workspaceId: $id) {
          customer {
            currentUsage
            billingPeriod { start end }
            invoices { invoiceId total status periodStart periodEnd reissuedInvoiceOf }
          }
        }
      }
    GRAPHQL

    def initialize(connection, env: ENV)
      @connection = connection
      @env = env
    end

    def charges(_today)
      customer = fetch.dig("workspace", "customer") || raise(Error, "Railway não devolveu o workspace #{@connection.account_id}")
      invoices = Array(customer["invoices"]).filter_map { |invoice| invoice_charge(invoice) }
      invoices + estimate_charges(customer, invoices.flat_map(&:replaces))
    end

    private

    def invoice_charge(invoice)
      return if IGNORED_STATUSES.include?(invoice["status"].to_s.downcase) || !invoice["total"].to_i.positive?

      start = date(invoice["periodStart"])
      finish = date(invoice["periodEnd"])
      return unless start && finish

      paid = invoice["status"].to_s.downcase == "paid"
      replaces = [ estimate_id(start) ]
      replaces << "invoice:#{invoice['reissuedInvoiceOf']}" if invoice["reissuedInvoiceOf"].present?
      Charge.new(external_id: "invoice:#{invoice['invoiceId']}", competence: start.beginning_of_month, due_on: finish,
                 description: "Railway — fatura #{period_label(start, finish)}", currency: "USD",
                 amount_cents: invoice["total"].to_i, status: paid ? :paid : :pending, paid_on: (finish if paid), replaces: replaces)
    end

    # O consumo é em dólares; a fatura do ciclo, se já existir, substitui a estimativa.
    def estimate_charges(customer, replaced)
      start = date(customer.dig("billingPeriod", "start"))
      finish = date(customer.dig("billingPeriod", "end"))
      cents = Billing.to_cents(customer["currentUsage"] || 0)
      return [] unless start && finish && cents.positive?
      return [] if replaced.include?(estimate_id(start))

      [ Charge.new(external_id: estimate_id(start), competence: start.beginning_of_month, due_on: finish, status: :forecast,
                   description: "Railway — consumo #{period_label(start, finish)} (estimativa)", currency: "USD", amount_cents: cents) ]
    end

    def estimate_id(start) = "estimate:#{start.iso8601}"

    def period_label(start, finish) = "de #{I18n.l(start, format: '%d/%m')} a #{I18n.l(finish, format: '%d/%m/%Y')}"

    # O Railway manda as datas do ciclo em ISO 8601 (UTC) e as da fatura podem vir como timestamp
    # Unix (Stripe). A data vale em UTC: no fuso local o início do ciclo poderia cair no dia anterior.
    def date(value)
      text = value.to_s
      return if text.blank?

      (text.match?(/\A\d+\z/) ? Time.at(text.to_i) : Time.iso8601(text)).utc.to_date
    rescue ArgumentError
      nil
    end

    # Token de workspace vai no Authorization; um guia antigo do Railway usa Team-Access-Token.
    # Token não aceito não dá "Not Authorized" (dá "Workspace not found"), então qualquer erro
    # tenta o outro cabeçalho; se os dois falharem, vale o erro do Authorization.
    def fetch
      body = post("Authorization" => "Bearer #{token}")
      if body["errors"].present?
        retry_body = post("Team-Access-Token" => token)
        body = retry_body if retry_body["errors"].blank?
      end
      if body["errors"].present?
        raise Error, "Railway respondeu: #{Array(body['errors']).map { |e| e['message'] }.compact_blank.uniq.to_sentence}"
      end

      body["data"] || raise(Error, "Railway respondeu sem dados")
    end

    def post(auth)
      uri = URI(ENDPOINT)
      request = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json" }.merge(auth))
      request.body = JSON.generate(query: QUERY, variables: { id: @connection.account_id })
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end
      body = JSON.parse(response.body.presence || "{}")
      raise Error, "Railway respondeu HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess) || body["errors"].present?

      body
    rescue JSON::ParserError
      raise Error, "Railway respondeu algo que não é JSON (HTTP #{response&.code})"
    end

    def token = @env.fetch("BILLING_RAILWAY_API_TOKEN")
  end
end
