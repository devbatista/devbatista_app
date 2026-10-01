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

      [ companies, contacts, contracts ].compact.reject { |g| g.items.empty? }
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

    def money(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, unit: "R$", separator: ",", delimiter: ".", format: "%u %n", precision: 0)
    end
  end
end
