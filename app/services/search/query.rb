module Search
  # Busca em todos os tipos que o perfil pode ver; cada fase acrescenta os seus tipos.
  class Query
    LIMIT = 6
    Group = Struct.new(:label, :area, :items, keyword_init: true)
    Item = Struct.new(:title, :subtitle, :path, :badge, keyword_init: true)

    include Rails.application.routes.url_helpers

    def initialize(user, term)
      @user = user
      @term = term.to_s.strip
    end

    def groups
      return [] if @term.size < 2

      [ companies, contacts, contracts, projects, tickets, receivables, invoices, proposals, leads ].compact.reject { |g| g.items.empty? }
    end

    private

    def companies
      return unless @user.can_read?("clientes")

      mrr = CustomerService.active.group(:company_id).sum(:mrr_cents)
      items = Company.search(@term).by_name.limit(LIMIT).map do |c|
        Item.new(title: c.trade_name, subtitle: [ c.status_label, ("MRR #{money(mrr[c.id])}" if mrr[c.id]) ].compact.join(" · "), path: company_path(c))
      end
      Group.new(label: "Clientes", area: "clientes", items: items)
    end

    def contacts
      return unless @user.can_read?("clientes")

      items = Contact.search(@term).includes(:company).by_name.limit(LIMIT).map do |c|
        Item.new(title: c.name, subtitle: [ c.position, c.company.trade_name ].compact.join(" · "), path: company_path(c.company))
      end
      Group.new(label: "Contatos", area: "clientes", items: items)
    end

    def contracts
      return unless @user.can_read?("contratos")

      items = Contract.search(@term).includes(:company).order(number: :desc).limit(LIMIT).map do |c|
        Item.new(title: c.to_s, subtitle: "#{c.company.trade_name} · #{c.status_label}", path: contract_path(c))
      end
      Group.new(label: "Contratos", area: "contratos", items: items)
    end

    def projects
      return unless @user.can_read?("projetos")

      items = Project.search(@term).includes(:company).order(Arel.sql("projects.status IN ('done','cancelled')"), :due_date).limit(LIMIT).map do |p|
        Item.new(title: p.name, subtitle: "#{p.company.trade_name} · #{p.status_label}#{' · atrasado' if p.late?} · #{p.progress}%", path: project_path(p))
      end
      Group.new(label: "Projetos", area: "projetos", items: items)
    end

    def tickets
      return unless @user.can_read?("suporte")

      items = Ticket.search(@term).includes(:company).order(opened_at: :desc).limit(LIMIT).map do |t|
        Item.new(title: "#{t.code} — #{t.subject}", subtitle: "#{t.company.trade_name} · #{t.status_label} · #{t.priority_label}", path: ticket_path(t))
      end
      Group.new(label: "Chamados", area: "suporte", items: items)
    end

    # Faturas: títulos a receber, pelo cliente ou pela descrição.
    def receivables
      return unless @user.can_read?("financeiro")

      items = Receivable.search(@term).includes(:company).order(due_on: :desc).limit(LIMIT).map do |r|
        Item.new(title: "#{r.company.trade_name} — #{r.description}", subtitle: "#{r.status_label} · vence #{I18n.l(r.due_on)} · #{money(r.amount_cents)}",
                 path: receivables_path(empresa: r.company_id, periodo: r.due_on.strftime("%Y-%m")))
      end
      Group.new(label: "Faturas", area: "financeiro", items: items)
    end

    def invoices
      return unless @user.can_read?("financeiro")

      items = Invoice.search(@term).includes(:company).order(competence: :desc).limit(LIMIT).map do |i|
        Item.new(title: "#{i.code} — #{i.company.trade_name}", subtitle: "#{i.status_label} · #{i.competence.strftime('%m/%Y')} · #{money(i.amount_cents)}",
                 path: invoices_path(periodo: i.competence.strftime("%Y-%m"), q: i.number))
      end
      Group.new(label: "Notas fiscais", area: "financeiro", items: items)
    end

    def proposals
      return unless @user.can_read?("comercial")

      items = Proposal.search(@term).includes(:company, :lead).order(year: :desc, number: :desc).limit(LIMIT).map do |p|
        Item.new(title: "#{p.code} — #{p.title}", subtitle: "#{p.recipient_name} · #{p.status_label} · #{money(p.total_cents)}", path: proposal_path(p))
      end
      Group.new(label: "Propostas", area: "comercial", items: items)
    end

    def leads
      return unless @user.can_read?("comercial")

      items = Lead.search(@term).order(entered_on: :desc).limit(LIMIT).map do |l|
        Item.new(title: l.display_name, subtitle: "Lead · #{l.status_label} · #{l.origin_label}", path: lead_path(l))
      end
      Group.new(label: "Leads", area: "comercial", items: items)
    end

    def money(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, unit: "R$", separator: ",", delimiter: ".", format: "%u %n", precision: 0)
    end
  end
end
