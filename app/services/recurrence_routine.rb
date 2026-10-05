# Rotina de recorrências (RF 27), diária às 06:00 (RecurrenceJob) e pelo botão "Executar rotina
# agora". Idempotente: rodar duas vezes no mesmo dia não duplica título nem alerta.
#
# 1. gera os títulos que faltam até o horizonte (mês corrente + N meses, Configurações), a
#    receber a partir dos serviços contratados ativos e a pagar a partir das despesas
#    recorrentes ativas, como Previsto e uma única vez por competência;
# 2. cancela títulos em aberto posteriores ao encerramento do serviço ou da despesa;
# 3. passa a Pendente os previstos que chegaram ao mês de competência;
# 4. marca como Vencido o que passou do vencimento sem pagamento e avisa o financeiro;
# 5. atualiza a estimativa em reais das despesas em moeda estrangeira (PTAX do dia).
class RecurrenceRoutine
  attr_reader :today, :user

  def self.horizon(today = Date.current)
    (today.beginning_of_month >> Setting[:recurrence_months].to_i).end_of_month
  end

  # Vencimentos de uma regra entre `from` e `to`: a partir do mês de início, a cada `months`
  # meses, no dia de vencimento (ou no último dia do mês, se ele for menor).
  def self.due_dates(start_on, months, day, from, to)
    return [] unless start_on && months

    day ||= start_on.day
    month = start_on.beginning_of_month
    dates = []
    while (due = month.change(day: [ day, month.end_of_month.day ].min)) <= to
      dates << due if due >= from && due >= start_on
      month = month.next_month(months)
    end
    dates
  end

  def initialize(today = Date.current, user: nil)
    @today = today
    @user = user
  end

  def run!
    run = RecurrenceRun.create!(run_on: today, started_at: Time.current, user: user, horizon_on: self.class.horizon(today))
    warnings = []
    generated = generate_receivables + generate_payables(warnings)
    cancelled = cancel_after_end
    promote_forecasts
    overdue = mark_overdue
    refresh_estimates(warnings)
    run.update!(finished_at: Time.current, generated_count: generated, cancelled_count: cancelled, overdue_count: overdue,
                warnings: warnings.uniq.join("\n").presence)
    run
  end

  private

  def window
    today.beginning_of_month..self.class.horizon(today)
  end

  def generate_receivables
    CustomerService.active.recurring.includes(:service, :company, :contract).sum do |cs|
      months = CustomerService::PERIOD_MONTHS[cs.recurrence]
      self.class.due_dates(cs.start_date, months, cs.due_day, window.first, window.last).count do |due_on|
        competence = due_on.beginning_of_month
        next false if Receivable.exists?(customer_service_id: cs.id, competence: competence)

        Receivable.create!(customer_service: cs, company: cs.company, description: "#{cs.service.name} — #{month_label(due_on)}",
                           category: cs.service.name, amount_cents: cs.price_cents, competence: competence, due_on: due_on, status: "forecast")
      rescue ActiveRecord::RecordNotUnique
        false
      end
    end
  end

  def generate_payables(warnings)
    RecurringExpense.active.includes(:supplier).sum do |rule|
      rule.due_dates(window.first, window.last).count do |due_on|
        next false if Payable.exists?(recurring_expense_id: rule.id, competence: due_on.beginning_of_month)

        if rule.foreign? && (rate = ExchangeRate.lookup(rule.currency, today)).nil?
          warnings << "Sem cotação do #{rule.currency}: #{rule.description} (#{rule.supplier.name}) não foi gerada"
          next false
        end
        warnings << "Cotação do #{rule.currency} de hoje indisponível; estimativas com a de #{I18n.l(rate.quoted_on)}" if rate&.fallback
        rule.payables.create!(rule.payable_attributes(due_on).merge(status: "forecast"))
      rescue ActiveRecord::RecordNotUnique
        false
      end
    end
  end

  def cancel_after_end
    count = 0
    Receivable.open.joins(:customer_service).where(customer_services: { status: "ended" })
              .where("receivables.due_on > customer_services.ended_on").find_each do |r|
      r.cancel!("Cancelado: serviço encerrado em #{I18n.l(r.customer_service.ended_on)}.")
      count += 1
    end
    Payable.open.joins(:recurring_expense).where(recurring_expenses: { status: "ended" })
           .where("payables.due_on > recurring_expenses.ended_on").find_each do |p|
      p.cancel!("Cancelado: despesa recorrente encerrada em #{I18n.l(p.recurring_expense.ended_on)}.")
      count += 1
    end
    count
  end

  def promote_forecasts
    [ Receivable, Payable ].each do |model|
      model.forecast.where(competence: ..today.beginning_of_month).find_each { |t| t.update!(status: "pending") }
    end
  end

  # Vence no dia seguinte ao vencimento sem pagamento. O aviso sai uma vez por título, inclusive
  # para os lançados à mão já vencidos.
  def mark_overdue
    count = [ Receivable, Payable ].sum do |model|
      model.where(status: %w[forecast pending]).where(due_on: ...today).find_each.count { |t| t.update!(status: "overdue") }
    end
    routes = Rails.application.routes.url_helpers
    Receivable.overdue.includes(:company).find_each do |r|
      Notification.deliver!(kind: "receivable_overdue", level: "crit", notifiable: r, dedup_key: "receivable-#{r.id}-overdue",
                            title: "Recebimento vencido: #{r.company.trade_name} · #{r.description} · #{money(r.amount_cents)} (venceu #{I18n.l(r.due_on, format: '%d/%m')})",
                            path: routes.receivables_path(status: "overdue"))
    end
    Payable.overdue.includes(:supplier).find_each do |p|
      Notification.deliver!(kind: "payable_overdue", level: "warn", notifiable: p, dedup_key: "payable-#{p.id}-overdue",
                            title: "Conta a pagar vencida: #{p.supplier.name} · #{p.description} · #{money(p.amount_cents)} (venceu #{I18n.l(p.due_on, format: '%d/%m')})",
                            path: routes.payables_path(status: "overdue"))
    end
    count
  end

  def refresh_estimates(warnings)
    Payable.open.foreign.find_each do |payable|
      rate = ExchangeRate.lookup(payable.currency, today)
      warnings << "Cotação do #{payable.currency} de hoje indisponível; usada a de #{I18n.l(rate.quoted_on)}" if rate&.fallback
      payable.refresh_estimate!(today)
    end
  end

  def month_label(date)
    I18n.l(date, format: "%B/%Y").capitalize
  end

  def money(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, unit: "R$", separator: ",", delimiter: ".", format: "%u %n",
                                                                  precision: (cents % 100).zero? ? 0 : 2)
  end
end
