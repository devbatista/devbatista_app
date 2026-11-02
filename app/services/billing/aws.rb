module Billing
  # Faturas da AWS (Invoicing API) e estimativa do mês corrente (Cost Explorer).
  #
  # Credenciais: um usuário IAM só de leitura, com as permissões invoicing:ListInvoiceSummaries
  # e ce:GetCostAndUsage, nas variáveis BILLING_AWS_ACCESS_KEY_ID e BILLING_AWS_SECRET_ACCESS_KEY.
  # A conta (12 dígitos) vem da conexão. As duas APIs são globais e respondem em us-east-1.
  #
  # - Fatura (InvoiceType INVOICE) dos últimos meses → despesa com o vencimento da fatura, na moeda
  #   de pagamento (BRL quando a conta paga em reais, senão USD). Notas de crédito ficam de fora.
  # - Consumo do mês corrente até ontem → despesa Prevista ("estimate:2026-11"), cancelada quando
  #   a fatura daquele mês fecha. O Cost Explorer cobra US$ 0,01 por consulta: uma por dia.
  class Aws
    REGION = "us-east-1".freeze
    MONTHS_BACK = 3

    def initialize(connection, invoicing: nil, cost_explorer: nil, env: ENV)
      @connection = connection
      @invoicing = invoicing
      @cost_explorer = cost_explorer
      @env = env
    end

    def charges(today)
      invoices = invoice_charges(today)
      invoiced = invoices.map(&:competence)
      invoices + estimate_charges(today, invoiced)
    end

    private

    def invoice_charges(today)
      (0..MONTHS_BACK).flat_map do |back|
        month = (today << back).beginning_of_month
        invoicing.list_invoice_summaries(selector: { resource_type: "ACCOUNT_ID", value: @connection.account_id },
                                         filter: { billing_period: { month: month.month, year: month.year } })
                 .each_page.flat_map(&:invoice_summaries)
      end.uniq(&:invoice_id).filter_map { |summary| invoice_charge(summary) }
    end

    def invoice_charge(summary)
      return unless summary.invoice_type == "INVOICE" && summary.bill_type != "REFUND"

      amounts = [ summary.payment_currency_amount, summary.base_currency_amount ].compact
      amount = amounts.find { |a| ExchangeRate::CURRENCIES.key?(a.currency_code) }
      return unless amount && Billing.to_cents(amount.total_amount).positive?

      competence = Date.new(summary.billing_period.year, summary.billing_period.month)
      # A AWS manda a data como meia-noite UTC; no fuso local ela cairia no dia anterior.
      due_on = (summary.due_date || summary.issued_date).utc.to_date
      Charge.new(external_id: "invoice:#{summary.invoice_id}", competence: competence, due_on: due_on,
                 description: "AWS — fatura #{summary.invoice_id} (#{month_label(competence)})",
                 currency: amount.currency_code, amount_cents: Billing.to_cents(amount.total_amount),
                 replaces: [ estimate_id(competence) ])
    end

    # O Cost Explorer pede fim depois do início: no dia 1º ainda não há consumo do mês.
    def estimate_charges(today, invoiced)
      start = today.beginning_of_month
      return [] if today == start || invoiced.include?(start)

      result = cost_explorer.get_cost_and_usage(time_period: { start: start.iso8601, end: today.iso8601 },
                                                granularity: "MONTHLY", metrics: [ "UnblendedCost" ])
      cost = result.results_by_time.first&.total&.fetch("UnblendedCost", nil)
      return [] unless cost && Billing.to_cents(cost.amount).positive?

      [ Charge.new(external_id: estimate_id(start), competence: start, due_on: start.next_month + 2, status: :forecast,
                   description: "AWS — consumo de #{month_label(start)} (estimativa até #{I18n.l(today - 1, format: '%d/%m')})",
                   currency: cost.unit.to_s.upcase, amount_cents: Billing.to_cents(cost.amount)) ]
    end

    def estimate_id(month) = "estimate:#{month.strftime('%Y-%m')}"

    def month_label(date) = I18n.l(date, format: "%B/%Y").capitalize

    def credentials
      ::Aws::Credentials.new(@env.fetch("BILLING_AWS_ACCESS_KEY_ID"), @env.fetch("BILLING_AWS_SECRET_ACCESS_KEY"))
    end

    def invoicing
      @invoicing ||= begin
        require "aws-sdk-invoicing"
        ::Aws::Invoicing::Client.new(region: REGION, credentials: credentials)
      end
    end

    def cost_explorer
      @cost_explorer ||= begin
        require "aws-sdk-costexplorer"
        ::Aws::CostExplorer::Client.new(region: REGION, credentials: credentials)
      end
    end
  end
end
