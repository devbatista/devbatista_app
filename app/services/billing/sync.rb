module Billing
  # Lança em Despesas as cobranças de uma conexão (rotina diária e botão "Sincronizar agora").
  #
  # - Cria uma despesa por cobrança, pelo external_id; nas próximas rodadas só atualiza valor,
  #   vencimento e descrição. Despesa paga ou cancelada (à mão ou não) não é mais tocada.
  # - A estimativa do mês corrente entra como Prevista e é cancelada quando a fatura fecha.
  # - Pagamento: o que o fornecedor informar; senão, com cobrança automática no cartão
  #   (auto_paid), a despesa é dada como paga no vencimento. Em moeda estrangeira o valor em
  #   reais vira o da PTAX do dia do pagamento, como no pagamento manual.
  #
  # Falha na API não derruba a rotina: fica em last_error, aparece na tela e avisa o Financeiro.
  class Sync
    Result = Struct.new(:created, :updated, :paid, :cancelled, keyword_init: true) do
      def to_s
        parts = [ [ created, "nova" ], [ updated, "atualizada" ], [ paid, "paga" ], [ cancelled, "cancelada" ] ]
                .filter_map { |count, word| "#{count} #{count == 1 ? word : "#{word}s"}" if count.positive? }
        parts.any? ? parts.to_sentence : "nenhuma mudança"
      end
    end

    attr_reader :connection, :today

    def initialize(connection, today: Date.current, client: nil)
      @connection = connection
      @today = today
      @client = client
    end

    def self.run_all(today = Date.current)
      BillingConnection.active.find_each.map { |connection| new(connection, today: today).run }
    end

    # Devolve o Result, ou nil se a sincronização falhou (o motivo fica em last_error).
    def run
      result = Result.new(created: 0, updated: 0, paid: 0, cancelled: 0)
      charges = client.charges(today)
      Payable.transaction { charges.each { |charge| apply(charge, result) } }
      connection.update_columns(last_synced_at: Time.current, last_error: nil, updated_at: Time.current)
      result
    rescue StandardError => e
      fail_with(e)
      nil
    end

    private

    def client
      @client ||= begin
        missing = connection.missing_env
        raise Error, "Faltam as variáveis de ambiente #{missing.to_sentence}" if missing.any?

        connection.client
      end
    end

    def apply(charge, result)
      unless ExchangeRate::CURRENCIES.key?(charge.currency)
        raise Error, "Cobrança #{charge.external_id} em #{charge.currency}, moeda que o Admin não converte"
      end

      charge.replaces.each { |external_id| result.cancelled += 1 if cancel_replaced(external_id) }

      payable = connection.payables.find_or_initialize_by(external_id: charge.external_id)
      return if payable.persisted? && (payable.paid? || payable.cancelled?)

      created = payable.new_record?
      payable.assign_attributes(attributes_for(charge))
      payable.status = "forecast" if created && charge.forecast?
      changed = payable.changed?
      payable.save!

      if (paid_on = paid_on_for(charge))
        unless payable.register_payment!(paid_on: paid_on, notes: "Pagamento registrado pela sincronização com #{connection.provider_label}.")
          raise Error, "#{payable.description}: #{payable.errors.full_messages.to_sentence}"
        end
        result.paid += 1
      end

      if created then result.created += 1
      elsif changed then result.updated += 1
      end
    end

    def attributes_for(charge)
      base = { supplier: connection.supplier, description: charge.description, company_id: connection.company_id,
               cost_center: connection.cost_center, currency: charge.currency, competence: charge.competence, due_on: charge.due_on }
      charge.currency == "BRL" ? base.merge(amount_cents: charge.amount_cents, original_amount_cents: nil) : base.merge(original_amount_cents: charge.amount_cents)
    end

    def paid_on_for(charge)
      return charge.paid_on if charge.paid_on
      return if charge.forecast? || !connection.auto_paid?

      charge.due_on if charge.due_on <= today
    end

    def cancel_replaced(external_id)
      replaced = connection.payables.open.find_by(external_id: external_id)
      replaced&.cancel!("Substituída pela fatura fechada do #{connection.provider_label}.")
      replaced.present?
    end

    def fail_with(error)
      message = error.message.to_s.truncate(500)
      first_failure = connection.last_error.blank?
      connection.update_columns(last_error: message, updated_at: Time.current)
      Rails.logger.warn("[Billing::Sync] #{connection.name}: #{error.class}: #{message}")
      return unless first_failure

      Notification.deliver!(kind: "billing_sync_failed", level: "warn", notifiable: connection,
                            title: "A sincronização de cobranças com #{connection.name} falhou: #{message.truncate(120)}",
                            path: Rails.application.routes.url_helpers.billing_connections_path,
                            dedup_key: "billing-#{connection.id}-#{Date.current}")
    end
  end
end
