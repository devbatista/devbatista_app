# Menu lateral, trilha de navegação e ícones (docs/design/DESIGN-SYSTEM.md).
module NavigationHelper
  ICONS = {
    dash: "M4 4h7v7H4zM13 4h7v4h-7zM13 10h7v10h-7zM4 13h7v7H4z",
    com: "M3 5h18l-7 8v5l-4 2v-7z",
    cli: "M4 20V6l8-3v17M12 9h8v11M2 20h20M7 8h2M7 12h2M7 16h2M15 13h2M15 16h2",
    op: "M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01",
    fin: "M4 20V12M10 20V6M16 20v-9M21 20H3",
    tec: "M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01",
    prod: "M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9",
    ges: "M6 3h9l4 4v14H6zM14 3v5h5M9 13h7M9 17h5",
    adm: "M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M14 4v4M8 10v4M16 16v4",
    search: "M11 18a7 7 0 100-14 7 7 0 000 14zM21 21l-4.3-4.3",
    bell: "M6 8a6 6 0 1112 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.9 1.9 0 003.4 0",
    menu: "M4 6h16M4 12h16M4 18h16",
    chev: "M9 6l6 6-6 6",
    close: "M6 6l12 12M18 6L6 18",
    plus: "M12 5v14M5 12h14",
    logout: "M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10",
    lock: "M6 11h12v10H6zM8 11V7a4 4 0 118 0v4",
    eye: "M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12zM12 15a3 3 0 100-6 3 3 0 000 6z",
    edit: "M4 20h4L19 9l-4-4L4 16zM14 6l4 4",
    file: "M6 3h9l4 4v14H6zM14 3v5h5",
    upload: "M12 16V4M7 9l5-5 5 5M4 20h16",
    star: "M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z",
    phone: "M5 4h4l2 5-2.5 1.5a11 11 0 005 5L15 13l5 2v4a2 2 0 01-2 2A16 16 0 013 6a2 2 0 012-2",
    whatsapp: "M4 20l1.4-4.2A8 8 0 1112 20a8 8 0 01-3.8-1z",
    check: "M5 12l5 5L20 7",
    send: "M4 12l16-8-6 16-2-7z",
    x: "M6 6l12 12M18 6L6 18",
    swap: "M7 7h11l-3-3M17 17H6l3 3",
    clock: "M12 21a9 9 0 100-18 9 9 0 000 18zM12 7v5l3 2",
    alert: "M12 9v4M12 17h.01M10.3 3.9L1.8 18a2 2 0 001.7 3h17a2 2 0 001.7-3L13.7 3.9a2 2 0 00-3.4 0z",
    board: "M4 4h4v16H4zM10 4h4v10h-4zM16 4h4v13h-4z",
    list: "M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01"
  }.freeze

  # Grupos do menu. Cada item aponta para a rota (símbolo do helper de path) e a área da
  # matriz de permissões. Item com route: nil ainda não foi construído e aparece como "em breve".
  NAV = [
    { key: :dash, label: "Dashboard", area: "dashboard", route: :root_path },
    { key: :com, label: "Comercial", items: [
      [ "Leads", :leads_path, "comercial" ], [ "Oportunidades", :opportunities_path, "comercial" ],
      [ "Propostas", :proposals_path, "comercial" ], [ "Pipeline", :pipeline_path, "comercial" ]
    ] },
    { key: :cli, label: "Clientes", items: [
      [ "Empresas", :companies_path, "clientes" ], [ "Contatos", :contacts_path, "clientes" ],
      [ "Contratos", :contracts_path, "contratos" ], [ "Serviços contratados", :customer_services_path, "contratos" ]
    ] },
    { key: :op, label: "Operação", items: [
      [ "Projetos", :projects_path, "projetos" ], [ "Tarefas", :tasks_path, "projetos" ],
      [ "Suporte", :tickets_path, "suporte" ], [ "Horas trabalhadas", :time_entries_path, "horas" ]
    ] },
    { key: :fin, label: "Financeiro", items: [
      [ "Dashboard financeiro", nil, "financeiro" ], [ "Receitas", nil, "financeiro" ],
      [ "Despesas", nil, "financeiro" ], [ "Contas a receber", nil, "financeiro" ],
      [ "Contas a pagar", nil, "financeiro" ], [ "Recorrências", nil, "financeiro" ],
      [ "Notas fiscais", nil, "financeiro" ]
    ] },
    { key: :tec, label: "Tecnologia", items: [
      [ "Aplicações", nil, "tecnologia" ], [ "Servidores", nil, "tecnologia" ],
      [ "Domínios", nil, "tecnologia" ], [ "Bancos de dados", nil, "tecnologia" ],
      [ "Integrações", nil, "tecnologia" ], [ "Serviços externos", nil, "tecnologia" ]
    ] },
    { key: :prod, label: "Produtos", items: [
      [ "Produtos próprios", nil, "produtos" ], [ "Assinaturas", nil, "produtos" ],
      [ "Indicadores", nil, "produtos" ]
    ] },
    { key: :ges, label: "Gestão", items: [
      [ "Fornecedores", nil, "fornecedores" ], [ "Documentos", :documents_path, "documentos" ],
      [ "Relatórios", nil, "relatorios" ], [ "Indicadores", nil, "relatorios" ],
      [ "Rentabilidade", nil, "relatorios" ]
    ] },
    { key: :adm, label: "Administração", items: [
      [ "Usuários", :admin_users_path, "administracao" ], [ "Permissões", :admin_permissions_path, "administracao" ],
      [ "Logs", :admin_audit_logs_path, "administracao" ], [ "Configurações", :admin_settings_path, "administracao" ],
      [ "Catálogo de serviços", :admin_services_path, "administracao" ]
    ] }
  ].freeze

  def icon(name, size: 20, stroke: 1.6, **attrs)
    tag.svg(width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
            "stroke-width": stroke, "stroke-linecap": "round", "stroke-linejoin": "round",
            "aria-hidden": "true", **attrs) { tag.path(d: ICONS.fetch(name)) }
  end

  # Grupos visíveis para o usuário, só com os itens que o perfil pode ler.
  def navigation_for(user)
    NAV.filter_map do |group|
      if group[:items]
        items = group[:items].select { |(_label, _route, area)| user.can_read?(area) }
        group.merge(items: items) if items.any?
      elsif user.can_read?(group[:area])
        group
      end
    end
  end

  # Cada tela declara onde está no menu e a trilha:
  #   <% nav_location :adm, "Usuários" %>
  #   <% breadcrumb ["Administração"], ["Usuários"] %>
  def nav_location(group, item = nil)
    @nav_group = group
    @nav_item = item
  end

  def breadcrumb(*crumbs)
    @breadcrumb = crumbs
  end

  def breadcrumb_html
    crumbs = @breadcrumb || []
    safe_join(crumbs.each_with_index.map do |(label, path), index|
      if index == crumbs.size - 1
        tag.b(label)
      else
        safe_join([ path ? link_to(label, path) : label, tag.span("/", class: "sep") ])
      end
    end)
  end

  def nav_group_active?(group)
    @nav_group == group[:key]
  end

  def nav_item_active?(group, label)
    nav_group_active?(group) && @nav_item == label
  end
end
