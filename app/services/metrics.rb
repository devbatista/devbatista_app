# Indicadores calculados a partir dos registros (RF 3, 38, 39 e 40). Nenhum é digitado.
# Usado pelo dashboard executivo, pelos indicadores, pela rentabilidade e pelos relatórios.
#
# Regras adotadas (doc. 08):
# - MRR numa data: serviços contratados recorrentes vigentes na data (começaram até ela e não
#   foram encerrados antes dela), pelo valor atual de cada serviço. Suspensos ficam fora.
# - Churn do período: clientes com MRR no dia anterior ao início que terminam o período sem MRR
#   ÷ clientes com MRR no início. Cliente que volta depois de sair é reativação: o churn da
#   saída continua contando e a volta não entra em novos clientes nem no CAC.
# - CAC: despesas de Marketing e Comercial da competência ÷ novos clientes (passaram a Ativo
#   pela primeira vez no período).
class Metrics
  ACQUISITION_CATEGORIES = %w[Marketing Comercial].freeze

  attr_reader :range

  def initialize(range)
    @range = range.first.to_date..range.last.to_date
  end

  # Mesmo tamanho, imediatamente antes: mês anterior, trimestre anterior ou ano anterior.
  def self.previous_range(range)
    months = ((range.last.year * 12 + range.last.month) - (range.first.year * 12 + range.first.month)) + 1
    start = range.first.beginning_of_month << months
    start..(start >> (months - 1)).end_of_month
  end

  def self.months_in(range)
    first = range.first.beginning_of_month
    (0..).lazy.map { |i| first >> i }.take_while { |m| m <= range.last }.to_a
  end

  # Serviços contratados vigentes numa data: começaram até ela, não foram encerrados antes dela
  # e não estão suspensos.
  def self.services_at(date, company_id: nil, service_id: nil)
    scope = CustomerService.where.not(status: "suspended").where(start_date: ..date)
                           .where("customer_services.ended_on IS NULL OR customer_services.ended_on > ?", date)
    scope = scope.where(company_id: company_id) if company_id.present?
    scope = scope.where(service_id: service_id) if service_id.present?
    scope
  end

  # MRR por empresa numa data, em centavos.
  def self.mrr_by_company(date, company_id: nil, service_id: nil)
    services_at(date, company_id: company_id, service_id: service_id).recurring
      .pluck(:company_id, :price_cents, :recurrence)
      .each_with_object(Hash.new(0)) { |(id, price, rec), h| h[id] += CustomerService.mrr_for(price, rec) }
  end

  def self.mrr_at(date)
    date >= Date.current ? CustomerService.active.sum(:mrr_cents) : mrr_by_company(date).values.sum
  end

  def self.active_clients
    Company.active.where(id: CustomerService.active.select(:company_id))
  end

  # Clientes ativos numa data passada: empresas com serviço contratado vigente na data (o status
  # da empresa não tem histórico, então vale só para hoje).
  def self.clients_at(date)
    return active_clients.count if date >= Date.current

    services_at(date).distinct.count(:company_id)
  end

  # Custo mensal de infraestrutura pago pela DevBatista: servidores, serviços externos e domínios.
  def self.infrastructure_monthly_cents
    Server.sum(:monthly_cost_cents) +
      ExternalService.active.paid_by_devbatista.to_a.sum(&:monthly_brl_cents) +
      Domain.paid_by_devbatista.to_a.sum { |d| d.renewal_cost_brl_cents / 12 }
  end

  def months
    self.class.months_in(range)
  end

  def competence
    range.first.beginning_of_month..range.last
  end

  def revenues
    Receivable.where(competence: competence)
  end

  def billing
    Receivable.summary(revenues)
  end

  def expenses_cents
    Payable.not_cancelled.where(competence: competence).sum(:amount_cents)
  end

  def result_cents
    billing[:billed] - expenses_cents
  end

  def margin_percent
    billed = billing[:billed]
    (result_cents * 100.0 / billed).round(1) if billed.positive?
  end

  def mrr_end
    self.class.mrr_at(range.last)
  end

  def revenue_by_company
    revenues.not_cancelled.group(:company_id).sum(:amount_cents)
  end

  # Faturamento por serviço do catálogo (sem serviço: pela categoria).
  def revenue_by_service
    revenues.not_cancelled.left_joins(:service).group(Arel.sql("COALESCE(services.name, receivables.category)")).sum(:amount_cents)
  end

  def new_clients
    Company.where(customer_since: range)
  end

  def churn
    before = self.class.mrr_by_company(range.first - 1)
    after = self.class.mrr_by_company([ range.last, Date.current ].min)
    base = before.select { |_, cents| cents.positive? }
    lost = base.keys.reject { |id| after[id].positive? }
    returning = after.keys.select { |id| after[id].positive? && before[id].zero? }
    reactivated = returning.select { |id| CustomerService.where(company_id: id).where(start_date: ...range.first).exists? }
    {
      base: base.size, base_mrr: base.values.sum, lost: lost.size, lost_mrr: lost.sum { |id| before[id] },
      rate: (base.any? ? (lost.size * 100.0 / base.size).round(1) : nil),
      mrr_rate: (base.any? ? (lost.sum { |id| before[id] } * 100.0 / base.values.sum).round(1) : nil),
      lost_ids: lost, reactivated_ids: reactivated, before: before, after: after
    }
  end

  def acquisition_cents
    Payable.not_cancelled.where(competence: competence, category: ACQUISITION_CATEGORIES).sum(:amount_cents)
  end

  def cac_cents
    count = new_clients.count
    acquisition_cents / count if count.positive?
  end

  def ticket_cents
    clients = self.class.active_clients.count
    billing[:billed] / clients if clients.positive?
  end

  def infrastructure_cents
    self.class.infrastructure_monthly_cents * months.size
  end

  def hours_by_company
    TimeEntry.where(worked_on: range).group(:company_id).sum(:minutes)
  end

  def open_proposals
    scope = Proposal.where(status: %w[sent viewed])
    { count: scope.count, cents: scope.sum(:total_cents) }
  end

  # Conversão: leads recebidos no período que viraram negócio fechado, por origem.
  def conversion
    leads = Lead.where(entered_on: range)
    won = Opportunity.stage_won.where(lead_id: leads.select(:id)).distinct.pluck(:lead_id)
    by_origin = leads.group(:origin).count.map do |origin, total|
      closed = leads.where(origin: origin, id: won).count
      { origin: origin, label: Lead::ORIGIN_LABELS[origin], leads: total, won: closed }
    end
    { leads: leads.count, won: won.size, rate: (leads.exists? ? (won.size * 100.0 / leads.count).round(1) : nil),
      by_origin: by_origin.sort_by { |o| [ -o[:won], -o[:leads] ] } }
  end

  # Séries mês a mês dos últimos `count` meses até o fim do período.
  def monthly_series(count = 6)
    last = range.last.beginning_of_month
    months = (0...count).map { |i| last << (count - 1 - i) }
    revenue = Receivable.not_cancelled.where(competence: months.first..last).group(:competence).sum(:amount_cents)
    expense = Payable.not_cancelled.where(competence: months.first..last).group(:competence).sum(:amount_cents)
    months.map do |m|
      close = m == Date.current.beginning_of_month ? Date.current : m.end_of_month
      { month: m, revenue: revenue[m].to_i, expense: expense[m].to_i, result: revenue[m].to_i - expense[m].to_i, mrr: self.class.mrr_at(close) }
    end
  end

  # Rentabilidade por cliente (RF 39): receita da competência menos custos diretos — serviços
  # externos pagos pela DevBatista, servidores, domínios pagos pela DevBatista (anual ÷ 12) e
  # despesas com centro de custo no cliente. Despesa ligada a um serviço externo é o mesmo gasto
  # do serviço e não entra de novo.
  def profitability
    revenue = revenue_by_company
    factor = months.size
    costs = Hash.new { |h, k| h[k] = [] }
    Server.includes(:supplier).find_each { |s| costs[s.company_id] << cost_line(s.name, s.monthly_cost_cents * factor, "Servidor · #{s.supplier.name}", s) }
    ExternalService.active.paid_by_devbatista.includes(:supplier, :app).find_each do |s|
      costs[s.company_id] << cost_line(s.to_s, s.monthly_brl_cents * factor, "Serviço externo pago pela DevBatista#{" · #{s.app.name}" if s.app}", s)
    end
    Domain.paid_by_devbatista.find_each { |d| costs[d.company_id] << cost_line(d.name, d.renewal_cost_brl_cents * factor / 12, "Domínio pago pela DevBatista (anual ÷ 12)", d) }
    Payable.not_cancelled.where(competence: competence, external_service_id: nil).where.not(company_id: nil).includes(:supplier).find_each do |p|
      costs[p.company_id] << cost_line(p.supplier.name, p.amount_cents, "Despesa com centro de custo no cliente · #{p.description}", p)
    end
    ids = (revenue.keys + costs.keys).uniq
    companies = Company.where(id: ids).index_by(&:id)
    ids.map do |id|
      rev = revenue[id].to_i
      cost = costs[id].sum { |c| c[:cents] }
      { company: companies[id], revenue: rev, cost: cost, margin: rev - cost, margin_percent: (rev.positive? ? ((rev - cost) * 100.0 / rev).round(1) : nil),
        lines: costs[id].sort_by { |c| -c[:cents] } }
    end
  end

  private

  def cost_line(label, cents, origin, record)
    { label: label, cents: cents, origin: origin, record: record }
  end
end
