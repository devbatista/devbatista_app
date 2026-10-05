# Os 19 relatórios básicos (RF 38), em 4 áreas. Cada relatório declara quem pode vê-lo (pela
# área de origem dos dados) e se é financeiro — os financeiros também filtram por cliente e
# serviço. O resultado é uma tabela (colunas tipadas + linhas), com gráfico e resumo opcionais;
# a mesma tabela vira o CSV.
class ReportCatalog
  Column = Data.define(:label, :type) # :text, :money, :count, :hours, :percent, :date
  Chart = Data.define(:title, :type, :rows)
  Result = Data.define(:columns, :rows, :footer, :chart, :callout, :note) do
    def initialize(columns:, rows:, footer: nil, chart: nil, callout: nil, note: nil) = super
  end
  Report = Data.define(:key, :group, :title, :description, :financial, :visible) do
    def visible_to?(user) = visible.call(user)
    def builder_method = key.tr("-", "_")
  end

  GROUPS = { "financeiro" => "Financeiro", "comercial" => "Comercial", "clientes" => "Clientes", "operacao" => "Operação" }.freeze

  FINANCIAL = ->(user) { user.sees_financials? }
  def self.area(name) = ->(user) { user.can_read?(name) }

  REPORTS = [
    Report.new("faturamento", "financeiro", "Faturamento", "Receitas por competência, mês a mês, com recebido, a receber e vencido.", true, FINANCIAL),
    Report.new("receita-por-cliente", "financeiro", "Receita por cliente", "Quanto cada cliente faturou e sua fatia do total, recorrente e projeto.", true, FINANCIAL),
    Report.new("receita-por-servico", "financeiro", "Receita por serviço", "Faturamento distribuído pelos serviços do catálogo.", true, FINANCIAL),
    Report.new("despesas", "financeiro", "Despesas", "Despesas por categoria, fornecedor e centro de custo.", true, FINANCIAL),
    Report.new("resultado", "financeiro", "Resultado", "Faturamento menos despesas e margem do período.", true, FINANCIAL),
    Report.new("mrr", "financeiro", "MRR", "Evolução da receita recorrente: novo, expansão, contração e perdido.", true, FINANCIAL),
    Report.new("leads", "comercial", "Leads", "Leads recebidos no período, por etapa e responsável.", false, area("comercial")),
    Report.new("origem-dos-leads", "comercial", "Origem dos leads", "De onde vieram: WhatsApp, Indicação, Site, Meta Ads, Google Ads e demais.", false, area("comercial")),
    Report.new("oportunidades", "comercial", "Oportunidades", "Oportunidades por etapa do pipeline, valor e motivo de perda.", false, area("comercial")),
    Report.new("propostas", "comercial", "Propostas", "Propostas enviadas, visualizadas, aceitas, recusadas e expiradas.", false, area("comercial")),
    Report.new("conversao", "comercial", "Conversão", "Negócios fechados sobre leads recebidos, total e por origem.", false, area("comercial")),
    Report.new("clientes-ativos", "clientes", "Clientes ativos", "Empresas com ao menos um serviço contratado vigente no fim do período.", false, area("clientes")),
    Report.new("novos-clientes", "clientes", "Novos clientes", "Empresas que passaram a Ativo no período, com origem e primeiro serviço.", false, area("clientes")),
    Report.new("churn", "clientes", "Churn", "Clientes e MRR perdidos sobre a base do início do período.", false, area("clientes")),
    Report.new("mrr-por-cliente", "clientes", "MRR por cliente", "Receita recorrente mensal de cada cliente e sua composição.", true, FINANCIAL),
    Report.new("projetos", "operacao", "Projetos", "Projetos por status, progresso, prazo e atraso.", false, area("projetos")),
    Report.new("horas", "operacao", "Horas", "Horas registradas por cliente, projeto e usuário.", false, area("horas")),
    Report.new("chamados", "operacao", "Chamados", "Chamados abertos e resolvidos, por prioridade, cliente e tempo de resolução.", false, area("suporte")),
    Report.new("tarefas", "operacao", "Tarefas", "Tarefas concluídas, abertas e atrasadas por responsável.", false, area("projetos"))
  ].freeze

  def self.find(key) = REPORTS.find { |r| r.key == key }
  def self.visible_to(user) = REPORTS.select { |r| r.visible_to?(user) }

  # range: período; company_id/service_id: filtros dos financeiros; scope: policy_scope do usuário.
  def initialize(report, range:, user:, scope:, company_id: nil, service_id: nil)
    @report = report
    @range = range.first.to_date..range.last.to_date
    @user = user
    @scope = scope
    @company_id = (company_id.presence if report.financial)
    @service_id = (service_id.presence if report.financial)
  end

  def result
    @result ||= send(@report.builder_method)
  end

  private

  attr_reader :range, :user, :company_id, :service_id

  def scope(model) = @scope.call(model)
  def financial? = user.sees_financials?
  def col(label, type = :text) = Column.new(label, type)
  def competence = range.first.beginning_of_month..range.last
  def months = Metrics.months_in(range)
  def month_name(month) = I18n.l(month, format: "%B/%Y").capitalize
  def close = [ range.last, Date.current ].min
  def share(part, total) = (total.positive? ? (part * 100.0 / total).round(1) : nil)
  def names(model, ids, attr = :trade_name) = model.where(id: ids.compact.uniq).pluck(:id, attr).to_h

  def receivables
    rel = scope(Receivable).where(competence: competence)
    rel = rel.where(company_id: company_id) if company_id
    rel = rel.where(service_id: service_id) if service_id
    rel
  end

  def payables
    rel = scope(Payable).not_cancelled.where(competence: competence)
    rel = rel.where(company_id: company_id) if company_id
    rel
  end

  # ── Financeiro ──────────────────────────────────────────────────────────

  def faturamento
    sums = receivables.group(:competence, :status).sum(:amount_cents)
    rows = months.map do |m|
      by = sums.select { |(c, _), _| c == m }.transform_keys(&:last)
      paid = by["paid"].to_i
      open = by["forecast"].to_i + by["pending"].to_i
      overdue = by["overdue"].to_i
      [ month_name(m), paid + open + overdue, paid, open, overdue ]
    end
    footer = [ "Total", *(1..4).map { |i| rows.sum { |r| r[i] } } ]
    Result.new(
      columns: [ col("Mês"), col("Faturado", :money), col("Recebido", :money), col("A receber", :money), col("Vencido", :money) ],
      rows: rows, footer: footer,
      chart: Chart.new("Faturado por mês", :money, rows.map { |r| [ r[0], r[1] ] }),
      callout: ("Recebido #{fmt_pct(share(footer[2], footer[1]))} do faturado; #{brl(footer[4])} vencido." if footer[1].positive?)
    )
  end

  def receita_por_cliente
    sums = receivables.not_cancelled.group(:company_id, Arel.sql("receivables.customer_service_id IS NOT NULL")).sum(:amount_cents)
    totals = Hash.new { |h, k| h[k] = [ 0, 0 ] }
    sums.each { |(id, recurring), cents| totals[id][recurring ? 0 : 1] += cents }
    total = totals.values.sum(&:sum)
    companies = names(Company, totals.keys)
    rows = totals.map { |id, (rec, other)| [ companies[id], rec, other, rec + other, share(rec + other, total) ] }.sort_by { |r| -r[3] }
    recurring = rows.sum { |r| r[1] }
    top5 = rows.first(5).sum { |r| r[3] }
    Result.new(
      columns: [ col("Cliente"), col("Recorrente", :money), col("Projetos e avulsos", :money), col("Total", :money), col("% do total", :percent) ],
      rows: rows, footer: [ "Total · #{rows.size} clientes", recurring, total - recurring, total, (100.0 if total.positive?) ],
      chart: Chart.new("Participação no faturamento", :money, rows.map { |r| [ r[0], r[3] ] }),
      callout: ("Os #{[ rows.size, 5 ].min} maiores clientes concentram #{fmt_pct(share(top5, total))} do faturamento. Recorrente responde por #{fmt_pct(share(recurring, total))}." if total.positive?)
    )
  end

  def receita_por_servico
    rel = receivables.not_cancelled.left_joins(:service).group(Arel.sql("COALESCE(services.name, receivables.category)"))
    sums = rel.sum(:amount_cents)
    counts = rel.count
    total = sums.values.sum
    rows = sums.map { |name, cents| [ name, counts[name], cents, share(cents, total) ] }.sort_by { |r| -r[2] }
    Result.new(
      columns: [ col("Serviço"), col("Títulos", :count), col("Total", :money), col("% do total", :percent) ],
      rows: rows, footer: [ "Total", rows.sum { |r| r[1] }, total, (100.0 if total.positive?) ],
      chart: Chart.new("Faturamento por serviço", :money, rows.map { |r| [ r[0], r[2] ] }),
      note: "Receita sem serviço do catálogo aparece pela categoria."
    )
  end

  def despesas
    sums = payables.group(:category, :supplier_id, :company_id, :cost_center).sum(:amount_cents)
    total = sums.values.sum
    suppliers = names(Supplier, sums.keys.map { |k| k[1] }, :name)
    companies = names(Company, sums.keys.map { |k| k[2] })
    rows = sums.map { |(category, supplier, company, center), cents| [ category, suppliers[supplier], company ? companies[company] : center, cents, share(cents, total) ] }
               .sort_by { |r| [ r[0], -r[3] ] }
    by_category = rows.group_by(&:first).transform_values { |rs| rs.sum { |r| r[3] } }.sort_by { |_, v| -v }
    Result.new(
      columns: [ col("Categoria"), col("Fornecedor"), col("Centro de custo"), col("Total", :money), col("% do total", :percent) ],
      rows: rows, footer: [ "Total", "", "", total, (100.0 if total.positive?) ],
      chart: Chart.new("Despesas por categoria", :money, by_category),
      note: ("O filtro de serviço não se aplica a despesas." if @report.financial && service_id)
    )
  end

  def resultado
    revenue = receivables.not_cancelled.group(:competence).sum(:amount_cents)
    expense = payables.group(:competence).sum(:amount_cents)
    rows = months.map do |m|
      r = revenue[m].to_i
      e = expense[m].to_i
      [ month_name(m), r, e, r - e, share(r - e, r) ]
    end
    r, e = rows.sum { |x| x[1] }, rows.sum { |x| x[2] }
    Result.new(
      columns: [ col("Mês"), col("Faturamento", :money), col("Despesas", :money), col("Resultado", :money), col("Margem", :percent) ],
      rows: rows, footer: [ "Total", r, e, r - e, share(r - e, r) ],
      chart: Chart.new("Faturamento por mês", :money, rows.map { |x| [ x[0], x[1] ] }),
      callout: ("Resultado de #{brl(r - e)} no período, margem de #{fmt_pct(share(r - e, r))}." if r.positive?),
      note: ("Com filtro de cliente, as despesas são as com centro de custo no cliente." if company_id)
    )
  end

  def mrr
    rows = months.map do |m|
      before = Metrics.mrr_by_company(m - 1, company_id: company_id, service_id: service_id)
      after = Metrics.mrr_by_company([ m.end_of_month, Date.current ].min, company_id: company_id, service_id: service_id)
      moves = Hash.new(0)
      (before.keys | after.keys).each do |id|
        b, a = before[id], after[id]
        if b.zero? then moves[:new] += a
        elsif a.zero? then moves[:lost] += b
        elsif a > b then moves[:expansion] += a - b
        else moves[:contraction] += b - a
        end
      end
      [ month_name(m), before.values.sum, moves[:new], moves[:expansion], moves[:contraction], moves[:lost], after.values.sum ]
    end
    Result.new(
      columns: [ col("Mês"), col("MRR no início", :money), col("Novo", :money), col("Expansão", :money), col("Contração", :money), col("Perdido", :money), col("MRR no fim", :money) ],
      rows: rows, footer: ([ "Período", rows.first[1], *(2..5).map { |i| rows.sum { |r| r[i] } }, rows.last[6] ] if rows.any?),
      chart: Chart.new("MRR no fim de cada mês", :money, rows.map { |r| [ r[0], r[6] ] }),
      note: "MRR pelo valor atual de cada serviço contratado; suspensos ficam fora."
    )
  end

  # ── Comercial ───────────────────────────────────────────────────────────

  def leads
    list = scope(Lead).where(entered_on: range).includes(:user).order(:entered_on, :id).to_a
    rows = list.map { |l| [ l.name, l.company_name, l.origin_label, l.status_label, l.user&.name, l.entered_on ] }
    converted = list.count(&:status_converted?)
    Result.new(
      columns: [ col("Lead"), col("Empresa"), col("Origem"), col("Etapa"), col("Responsável"), col("Entrada", :date) ],
      rows: rows,
      chart: Chart.new("Leads por etapa", :count, list.group_by(&:status_label).map { |k, v| [ k, v.size ] }.sort_by { |_, v| -v }),
      callout: ("#{count(list.size, 'lead recebido', 'leads recebidos')}; #{count(converted, 'convertido', 'convertidos')} e #{count(list.count(&:status_lost?), 'perdido', 'perdidos')}." if list.any?)
    )
  end

  def origem_dos_leads
    conversion = Metrics.new(range).conversion
    total = conversion[:leads]
    rows = conversion[:by_origin].sort_by { |o| -o[:leads] }.map { |o| [ o[:label], o[:leads], share(o[:leads], total), o[:won] ] }
    Result.new(
      columns: [ col("Origem"), col("Leads", :count), col("% dos leads", :percent), col("Fechados", :count) ],
      rows: rows, footer: [ "Total", total, (100.0 if total.positive?), conversion[:won] ],
      chart: Chart.new("Leads por origem", :count, rows.map { |r| [ r[0], r[1] ] })
    )
  end

  def oportunidades
    list = scope(Opportunity).includes(:company, :lead, :user)
                             .where("opportunities.created_at BETWEEN :from AND :to OR opportunities.closed_on BETWEEN :d1 AND :d2",
                                    from: range.first.beginning_of_day, to: range.last.end_of_day, d1: range.first, d2: range.last)
                             .order(:created_at).to_a
    rows = list.map { |o| [ o.title, o.company&.trade_name || o.lead&.company_name, o.stage_label, o.estimated_value_cents, o.user&.name, o.lost_reason ] }
    by_stage = list.group_by(&:stage_label).map { |k, v| [ k, v.sum { |o| o.estimated_value_cents.to_i } ] }.sort_by { |_, v| -v }
    Result.new(
      columns: [ col("Oportunidade"), col("Cliente ou lead"), col("Etapa"), col("Valor estimado", :money), col("Responsável"), col("Motivo de perda") ],
      rows: rows, footer: [ "Total · #{rows.size}", "", "", list.sum { |o| o.estimated_value_cents.to_i }, "", "" ],
      chart: Chart.new("Valor por etapa", :money, by_stage),
      note: "Oportunidades criadas ou fechadas no período."
    )
  end

  def propostas
    list = scope(Proposal).includes(:company, :lead)
                          .where("COALESCE(proposals.sent_at, proposals.created_at) BETWEEN ? AND ?", range.first.beginning_of_day, range.last.end_of_day)
                          .order(:year, :number).to_a
    rows = list.map { |p| [ p.code, p.title, p.company&.trade_name || p.lead&.company_name, p.status_label, p.total_cents, p.sent_at&.to_date, p.valid_until ] }
    Result.new(
      columns: [ col("Proposta"), col("Título"), col("Cliente ou lead"), col("Status"), col("Valor", :money), col("Enviada em", :date), col("Validade", :date) ],
      rows: rows, footer: [ "Total · #{rows.size}", "", "", "", list.sum(&:total_cents), nil, nil ],
      chart: Chart.new("Propostas por status", :count, list.group_by(&:status_label).map { |k, v| [ k, v.size ] }.sort_by { |_, v| -v }),
      note: "Propostas enviadas no período (rascunhos pela data de criação)."
    )
  end

  def conversao
    conversion = Metrics.new(range).conversion
    rows = conversion[:by_origin].map { |o| [ o[:label], o[:leads], o[:won], share(o[:won], o[:leads]) ] }
    Result.new(
      columns: [ col("Origem"), col("Leads recebidos", :count), col("Fechados", :count), col("Conversão", :percent) ],
      rows: rows, footer: [ "Total", conversion[:leads], conversion[:won], conversion[:rate] ],
      chart: Chart.new("Conversão por origem", :percent, rows.map { |r| [ r[0], r[3].to_f ] }),
      callout: ("#{count(conversion[:won], 'negócio fechado', 'negócios fechados')} de #{count(conversion[:leads], 'lead', 'leads')}: #{fmt_pct(conversion[:rate])}." if conversion[:leads].positive?),
      note: "Fechado = oportunidade do lead na etapa Fechado."
    )
  end

  # ── Clientes ────────────────────────────────────────────────────────────

  def clientes_ativos
    services = Metrics.services_at(close).includes(:service).to_a.group_by(&:company_id)
    companies = scope(Company).where(id: services.keys).order(:trade_name).to_a
    companies = companies.select(&:active?) if close >= Date.current
    rows = companies.map do |c|
      list = services[c.id]
      row = [ c.trade_name, list.map { |s| s.service&.name || s.description }.uniq.join(", "), list.size, c.customer_since ]
      financial? ? row + [ list.sum { |s| s.recurrence == "one_off" ? 0 : CustomerService.mrr_for(s.price_cents, s.recurrence) } ] : row
    end
    columns = [ col("Cliente"), col("Serviços vigentes"), col("Qtd.", :count), col("Cliente desde", :date) ]
    columns << col("MRR", :money) if financial?
    Result.new(
      columns: columns, rows: rows,
      footer: ([ "Total · #{rows.size} clientes", "", rows.sum { |r| r[2] }, nil, *(rows.sum { |r| r[4] } if financial?) ] if rows.any?),
      chart: (Chart.new("MRR por cliente", :money, rows.map { |r| [ r[0], r[4] ] }.sort_by { |_, v| -v }) if financial?),
      note: "Posição em #{I18n.l(close)}."
    )
  end

  def novos_clientes
    companies = scope(Company).where(customer_since: range).order(:customer_since).to_a
    origins = Lead.where(company_id: companies.map(&:id)).order(:entered_on).pluck(:company_id, :origin).to_h
    first_services = CustomerService.where(company_id: companies.map(&:id)).includes(:service).order(:start_date).group_by(&:company_id)
    rows = companies.map do |c|
      first = first_services[c.id]&.first
      [ c.trade_name, c.customer_since, (Lead::ORIGIN_LABELS[origins[c.id]] || "—"), (first ? first.service&.name || first.description : "—"), c.status_label ]
    end
    Result.new(
      columns: [ col("Cliente"), col("Cliente desde", :date), col("Origem"), col("Primeiro serviço"), col("Status") ],
      rows: rows,
      note: "Cliente que volta depois de sair é reativação e não entra aqui (veja Churn)."
    )
  end

  def churn
    data = Metrics.new(range).churn
    ids = data[:lost_ids] + data[:reactivated_ids]
    companies = names(Company, ids)
    rows = data[:lost_ids].map { |id| [ companies[id], "Perdido", *(data[:before][id] if financial?) ] } +
           data[:reactivated_ids].map { |id| [ companies[id], "Reativado", *(data[:after][id] if financial?) ] }
    columns = [ col("Cliente"), col("Situação") ]
    columns << col("MRR", :money) if financial?
    mrr_text = financial? && data[:base].positive? ? " MRR perdido: #{brl(data[:lost_mrr])} (#{fmt_pct(data[:mrr_rate])} do MRR do início)." : ""
    Result.new(
      columns: columns, rows: rows,
      callout: (data[:base].positive? ? "Churn de #{fmt_pct(data[:rate])}: #{data[:lost]} de #{data[:base]} clientes com MRR no início do período.#{mrr_text}" : "Nenhum cliente com MRR no início do período."),
      note: "Perdido = tinha MRR no dia anterior ao início e terminou o período sem MRR. Reativado = voltou depois de sair; conta à parte, não como novo cliente."
    )
  end

  def mrr_por_cliente
    services = Metrics.services_at(close, company_id: company_id, service_id: service_id).recurring.includes(:service).to_a.group_by(&:company_id)
    companies = names(Company, services.keys)
    totals = services.transform_values { |list| list.sum { |s| CustomerService.mrr_for(s.price_cents, s.recurrence) } }
    total = totals.values.sum
    rows = services.map do |id, list|
      composition = list.map { |s| "#{s.service&.name || s.description} #{brl(CustomerService.mrr_for(s.price_cents, s.recurrence))}" }.join(" + ")
      [ companies[id], composition, list.size, totals[id], share(totals[id], total) ]
    end.sort_by { |r| -r[3] }
    Result.new(
      columns: [ col("Cliente"), col("Composição"), col("Serviços", :count), col("MRR", :money), col("% do MRR", :percent) ],
      rows: rows, footer: [ "Total · #{rows.size} clientes", "", rows.sum { |r| r[2] }, total, (100.0 if total.positive?) ],
      chart: Chart.new("MRR por cliente", :money, rows.map { |r| [ r[0], r[3] ] }),
      note: "Posição em #{I18n.l(close)}; serviços recorrentes mensalizados pelo valor atual."
    )
  end

  # ── Operação ────────────────────────────────────────────────────────────

  def projetos
    list = scope(Project).includes(:company, :user).where(start_date: ..range.last)
                         .where("projects.closed_on IS NULL OR projects.closed_on >= ?", range.first).order(:due_date).to_a
    rows = list.map do |p|
      late = p.late?(close) ? (close - p.due_date).to_i : 0
      [ p.name, p.company.trade_name, p.status_label, p.user&.name, p.progress.to_f, p.due_date, late ]
    end
    Result.new(
      columns: [ col("Projeto"), col("Cliente"), col("Status"), col("Responsável"), col("Progresso", :percent), col("Prazo", :date), col("Dias de atraso", :count) ],
      rows: rows,
      chart: Chart.new("Projetos por status", :count, list.group_by(&:status_label).map { |k, v| [ k, v.size ] }.sort_by { |_, v| -v }),
      callout: ("#{rows.count { |r| r[6].positive? }} de #{count(rows.size, 'projeto', 'projetos')} com atraso em #{I18n.l(close)}." if rows.any?),
      note: "Projetos em andamento em algum momento do período."
    )
  end

  def horas
    sums = scope(TimeEntry).where(worked_on: range).group(:company_id, :project_id, :user_id).sum(:minutes)
    companies = names(Company, sums.keys.map(&:first))
    projects = names(Project, sums.keys.map { |k| k[1] }, :name)
    users = names(User, sums.keys.map(&:last), :name)
    rows = sums.map { |(c, p, u), minutes| [ companies[c], projects[p] || "Sem projeto", users[u], minutes ] }.sort_by { |r| [ r[0].to_s, -r[3] ] }
    by_company = rows.group_by(&:first).transform_values { |rs| rs.sum(&:last) }.sort_by { |_, v| -v }
    Result.new(
      columns: [ col("Cliente"), col("Projeto"), col("Usuário"), col("Horas", :hours) ],
      rows: rows, footer: [ "Total", "", "", rows.sum(&:last) ],
      chart: Chart.new("Horas por cliente", :hours, by_company),
      note: "Horas faturáveis e não faturáveis ficam para depois do MVP: todas as horas aparecem aqui."
    )
  end

  def chamados
    from, to = range.first.beginning_of_day, range.last.end_of_day
    list = scope(Ticket).includes(:company).where("tickets.opened_at BETWEEN :from AND :to OR tickets.resolved_at BETWEEN :from AND :to", from: from, to: to)
                        .order(:opened_at).to_a
    rows = list.map { |t| [ t.code, t.subject, t.company.trade_name, t.priority_label, t.status_label, t.opened_at.to_date, t.resolved_at&.to_date, t.resolution_minutes ] }
    resolved = list.select { |t| t.resolved_at&.between?(from, to) }
    average = resolved.any? ? resolved.sum(&:resolution_minutes) / resolved.size : nil
    Result.new(
      columns: [ col("Chamado"), col("Assunto"), col("Cliente"), col("Prioridade"), col("Status"), col("Aberto em", :date), col("Resolvido em", :date), col("Tempo de resolução", :hours) ],
      rows: rows,
      chart: Chart.new("Chamados por prioridade", :count, Ticket::PRIORITY_LABELS.values.reverse.filter_map { |label| n = list.count { |t| t.priority_label == label }; [ label, n ] if n.positive? }),
      callout: ("#{count(list.count { |t| t.opened_at.between?(from, to) }, 'aberto', 'abertos')} e #{count(resolved.size, 'resolvido', 'resolvidos')} no período#{"; resolução média de #{TimeEntry.format_minutes(average)}" if average}." if list.any?)
    )
  end

  def tarefas
    tasks = scope(Task).where.not(user_id: nil)
    done = tasks.where(completed_on: range).group(:user_id).count
    open = tasks.where.not(status: "done").group(:user_id).count
    late = tasks.where.not(status: "done").where(due_on: ...Date.current).group(:user_id).count
    users = names(User, done.keys + open.keys, :name)
    rows = users.map { |id, name| [ name, done[id].to_i, open[id].to_i, late[id].to_i ] }.sort_by { |r| -r[1] }
    Result.new(
      columns: [ col("Responsável"), col("Concluídas no período", :count), col("Abertas hoje", :count), col("Atrasadas hoje", :count) ],
      rows: rows, footer: [ "Total", *(1..3).map { |i| rows.sum { |r| r[i] } } ],
      chart: Chart.new("Concluídas por responsável", :count, rows.map { |r| [ r[0], r[1] ] }),
      note: "Abertas e atrasadas são a posição de hoje."
    )
  end

  def brl(cents) = ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, unit: "R$", format: "%u %n", separator: ",", delimiter: ".", precision: (cents % 100).zero? ? 0 : 2)
  def count(number, one, many) = "#{number} #{number == 1 ? one : many}"
  def fmt_pct(value) = value.nil? ? "—" : "#{ActiveSupport::NumberHelper.number_to_rounded(value, precision: 1, separator: ',', strip_insignificant_zeros: true)}%"
end
