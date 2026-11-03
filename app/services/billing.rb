# Faturas de fornecedores puxadas pela API (BillingConnection). Cada cliente de API
# (Billing::Aws, Billing::Cloudflare, Billing::Railway) devolve as cobranças como Billing::Charge, e o
# Billing::Sync as transforma em despesas (Payable), igual para todos os fornecedores.
module Billing
  class Error < StandardError; end

  # Uma cobrança do fornecedor, já na forma de despesa.
  # - external_id: id estável no fornecedor (fatura, item do histórico ou "estimate:2026-11");
  # - amount_cents: na moeda da cobrança (currency);
  # - status: :forecast (estimativa do mês corrente), :pending ou :paid (com paid_on);
  # - replaces: external_ids que esta cobrança substitui (a fatura fechada substitui a estimativa).
  Charge = Struct.new(:external_id, :description, :competence, :due_on, :currency, :amount_cents, :status, :paid_on, :replaces,
                      keyword_init: true) do
    def initialize(status: :pending, replaces: [], **attributes)
      super
    end

    def forecast? = status == :forecast
  end

  # "12.34" (texto da API) em centavos.
  def self.to_cents(amount)
    (BigDecimal(amount.to_s) * 100).round.to_i
  end
end
