/* ==========================================================================
   Admin DevBatista — comportamento comum das telas do design.
   Cada página declara no <body>:
     data-group="fin"                 grupo ativo do menu
     data-item="Contas a receber"     item ativo do menu
     data-crumb='[["Financeiro"],["Contas a receber"]]'   trilha (texto, link opcional)
   e deixa vazios <aside class="side"></aside> e <header class="top"></header>.
   ========================================================================== */
(function () {
  'use strict';

  const ICON = {
    dash: 'M4 4h7v7H4zM13 4h7v4h-7zM13 10h7v10h-7zM4 13h7v7H4z',
    com: 'M3 5h18l-7 8v5l-4 2v-7z',
    cli: 'M4 20V6l8-3v17M12 9h8v11M2 20h20M7 8h2M7 12h2M7 16h2M15 13h2M15 16h2',
    op: 'M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01',
    fin: 'M4 20V12M10 20V6M16 20v-9M21 20H3',
    tec: 'M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01',
    prod: 'M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9',
    ges: 'M6 3h9l4 4v14H6zM14 3v5h5M9 13h7M9 17h5',
    adm: 'M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M14 4v4M8 10v4M16 16v4',
    search: 'M11 18a7 7 0 100-14 7 7 0 000 14zM21 21l-4.3-4.3',
    bell: 'M6 8a6 6 0 1112 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.9 1.9 0 003.4 0',
    menu: 'M4 6h16M4 12h16M4 18h16',
    chev: 'M9 6l6 6-6 6',
    close: 'M6 6l12 12M18 6L6 18'
  };

  const NAV = [
    { key: 'dash', label: 'Dashboard', href: 'dashboard.html', items: [] },
    { key: 'com', label: 'Comercial', items: [['Leads', 'leads.html'], ['Oportunidades', 'oportunidades.html'], ['Propostas', 'propostas.html'], ['Pipeline', 'pipeline.html']] },
    { key: 'cli', label: 'Clientes', items: [['Empresas', 'empresas.html'], ['Contatos', 'contatos.html'], ['Contratos', 'contratos.html'], ['Serviços contratados', 'servicos-contratados.html']] },
    { key: 'op', label: 'Operação', items: [['Projetos', 'projetos.html'], ['Tarefas', 'tarefas.html'], ['Suporte', 'chamados.html'], ['Horas trabalhadas', 'horas.html']] },
    { key: 'fin', label: 'Financeiro', items: [['Dashboard financeiro', 'financeiro.html'], ['Receitas', 'receitas.html'], ['Despesas', 'despesas.html'], ['Contas a receber', 'contas-receber.html'], ['Contas a pagar', 'contas-pagar.html'], ['Recorrências', 'recorrencias.html'], ['Notas fiscais', 'notas-fiscais.html']] },
    { key: 'tec', label: 'Tecnologia', items: [['Aplicações', 'aplicacoes.html'], ['Servidores', 'servidores.html'], ['Domínios', 'dominios.html'], ['Bancos de dados', 'bancos-dados.html'], ['Integrações', 'integracoes.html'], ['Serviços externos', 'servicos-externos.html']] },
    { key: 'prod', label: 'Produtos', items: [['Produtos próprios', 'produtos.html'], ['Assinaturas', 'assinaturas.html'], ['Indicadores', 'produtos-indicadores.html']] },
    { key: 'ges', label: 'Gestão', items: [['Fornecedores', 'fornecedores.html'], ['Documentos', 'documentos.html'], ['Relatórios', 'relatorios.html'], ['Indicadores', 'indicadores.html'], ['Rentabilidade', 'rentabilidade.html']] },
    { key: 'adm', label: 'Administração', items: [['Usuários', 'usuarios.html'], ['Permissões', 'permissoes.html'], ['Logs', 'logs.html'], ['Configurações', 'configuracoes.html']] }
  ];

  // Cada item principal do menu é uma pasta; as telas se ligam pelo nome do arquivo.
  const FOLDER = {
    dashboard: ['dashboard'],
    comercial: ['leads', 'lead', 'oportunidades', 'propostas', 'proposta', 'pipeline'],
    clientes: ['empresas', 'empresa', 'contatos', 'contratos', 'contrato', 'servicos-contratados'],
    operacao: ['projetos', 'projeto', 'tarefas', 'chamados', 'chamado', 'horas'],
    financeiro: ['financeiro', 'receitas', 'despesas', 'contas-receber', 'contas-pagar', 'recorrencias', 'notas-fiscais'],
    tecnologia: ['aplicacoes', 'aplicacao', 'servidores', 'dominios', 'bancos-dados', 'integracoes', 'servicos-externos'],
    produtos: ['produtos', 'assinaturas', 'produtos-indicadores'],
    gestao: ['fornecedores', 'documentos', 'relatorios', 'indicadores', 'rentabilidade'],
    administracao: ['usuarios', 'permissoes', 'logs', 'configuracoes', 'catalogo-servicos'],
    acesso: ['login', 'recuperar-senha'],
    geral: ['notificacoes', 'busca']
  };
  const WHERE = {};
  Object.keys(FOLDER).forEach((f) => FOLDER[f].forEach((n) => { WHERE[n] = f; }));
  const ROOT = new URL('..', document.currentScript.src).href;
  const page = (file) => {
    if (file.includes('/')) return new URL(file, document.baseURI).href; // já é um caminho relativo à página
    const n = file.replace(/\.html(#.*)?$/, '');
    return ROOT + (WHERE[n] ? WHERE[n] + '/' : '') + file;
  };
  const asset = (file) => ROOT + 'assets/' + file;

  const svg = (d, size, sw) =>
    `<svg width="${size || 20}" height="${size || 20}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw || 1.6}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${d}"></path></svg>`;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  const body = document.body;
  const group = body.dataset.group || '';
  const item = body.dataset.item || '';

  /* ---------- Sidebar ---------- */
  const side = document.querySelector('.side');
  if (side) {
    let html = `<div class="brand"><a href="${page('dashboard.html')}" aria-label="Início"><img src="${asset('logo-devbatista-branco.png')}" alt="DevBatista"></a><span class="badge b-info">Admin</span></div>`;
    html += '<nav aria-label="Menu principal" style="display:flex;flex-direction:column;gap:2px">';
    NAV.forEach((g) => {
      const on = g.key === group;
      if (!g.items.length) {
        html += `<a class="grp${on ? ' on' : ''}" href="${page(g.href)}"${on ? ' aria-current="page"' : ''}>${svg(ICON[g.key])}${g.label}</a>`;
        return;
      }
      html += `<button class="grp${on ? ' on open' : ''}" type="button" aria-expanded="${on}">${svg(ICON[g.key])}${g.label}<span class="chev">${svg(ICON.chev, 14, 2)}</span></button>`;
      html += '<div class="sub">' + g.items.map(([l, h]) => {
        const cur = on && l === item;
        return `<a class="it${cur ? ' on' : ''}" href="${page(h)}"${cur ? ' aria-current="page"' : ''}>${l}</a>`;
      }).join('') + '</div>';
    });
    html += '</nav>';
    html += `<a class="me" href="${page('usuarios.html')}" style="text-decoration:none"><span class="avatar">R</span><div>Rafael<small>Administrador</small></div></a>`;
    side.innerHTML = html;
    side.querySelectorAll('button.grp').forEach((b) => b.addEventListener('click', () => {
      b.classList.toggle('open');
      b.setAttribute('aria-expanded', b.classList.contains('open'));
    }));
  }

  /* ---------- Topbar ---------- */
  const top = document.querySelector('.top');
  if (top) {
    let crumb = [];
    try { crumb = JSON.parse(body.dataset.crumb || '[]'); } catch (e) { crumb = []; }
    const crumbHtml = crumb.map(([t, h], i) => {
      const last = i === crumb.length - 1;
      if (last) return `<b>${esc(t)}</b>`;
      return (h ? `<a href="${page(h)}">${esc(t)}</a>` : esc(t)) + '<span class="sep">/</span>';
    }).join('');
    top.innerHTML =
      `<button class="icon-btn ghost menu-btn" type="button" aria-label="Abrir menu" data-nav-toggle>${svg(ICON.menu, 22, 1.8)}</button>` +
      `<div class="crumb">${crumbHtml}</div>` +
      `<button class="search-trigger" type="button" data-search-open aria-label="Busca global">${svg(ICON.search, 16, 1.8)}<span>Buscar clientes, contratos, chamados…</span><span class="kbd">⌘K</span></button>` +
      `<button class="icon-btn" type="button" aria-label="Notificações, 4 não lidas" data-notif-toggle>${svg(ICON.bell)}<span class="dot"></span></button>` +
      `<a class="avatar" href="${page('usuarios.html')}" aria-label="Rafael, Administrador">R</a>`;

    // Notificações
    const pop = document.createElement('div');
    pop.className = 'popover';
    pop.setAttribute('role', 'dialog');
    pop.setAttribute('aria-label', 'Notificações');
    pop.innerHTML =
      '<div class="card-head"><h2>Notificações</h2><a href="' + page('notificacoes.html') + '" style="font-size:13px;font-weight:600">Ver todas</a></div>' +
      '<a class="notif" href="' + page('chamado.html') + '"><i class="crit"></i><div>Chamado crítico #2394 aberto para Empresa Delta<small>há 12 min · Suporte</small></div></a>' +
      '<a class="notif" href="' + page('contas-receber.html') + '"><i class="crit"></i><div>3 títulos vencidos somam R$ 4.300<small>hoje, 07:00 · Financeiro</small></div></a>' +
      '<a class="notif" href="' + page('contratos.html') + '"><i class="warn"></i><div>Contrato #098 da Empresa XYZ vence em 30 dias<small>hoje, 07:00 · Contratos</small></div></a>' +
      '<a class="notif" href="' + page('dominios.html') + '"><i class="warn"></i><div>Domínio acme.com.br vence em 7 dias, sem renovação automática<small>hoje, 07:00 · Tecnologia</small></div></a>' +
      '<a class="notif" href="' + page('propostas.html') + '"><i class="read"></i><div>Proposta “Integração ERP” expira em 3 dias<small>ontem · Comercial</small></div></a>';
    top.appendChild(pop);
    top.querySelector('[data-notif-toggle]').addEventListener('click', (e) => { e.stopPropagation(); pop.classList.toggle('open'); });
    document.addEventListener('click', (e) => { if (!pop.contains(e.target)) pop.classList.remove('open'); });

    top.querySelector('[data-nav-toggle]').addEventListener('click', (e) => { e.stopPropagation(); body.classList.toggle('nav-open'); });
    document.addEventListener('click', (e) => {
      if (body.classList.contains('nav-open') && side && !side.contains(e.target)) body.classList.remove('nav-open');
    });
  }

  /* ---------- Busca global (⌘K) ---------- */
  const RESULTS = [
    ['Clientes', 'Empresa ACME', 'Ativo · MRR R$ 3.800', 'empresa.html'],
    ['Clientes', 'Empresa XYZ', 'Ativo · MRR R$ 2.900', 'empresa.html'],
    ['Contratos', '#104 — Consultoria de TI', 'Empresa ACME', 'contrato.html'],
    ['Chamados', '#2381 — Erro ao gerar relatório', 'Empresa ACME · Resolvido', 'chamado.html'],
    ['Faturas', 'Setembro/2026 — R$ 3.800', 'Empresa ACME · Pago', 'contas-receber.html'],
    ['Aplicações', 'Portal ACME', 'Produção', 'aplicacao.html'],
    ['Propostas', 'Portal de Pedidos', 'Empresa XYZ · Enviada', 'proposta.html'],
    ['Projetos', 'Portal ACME — Fase 2', 'Em andamento', 'projeto.html']
  ];
  const pal = document.createElement('div');
  pal.className = 'palette';
  pal.setAttribute('role', 'dialog');
  pal.setAttribute('aria-label', 'Busca global');
  const ov = document.createElement('div');
  ov.className = 'overlay';
  document.body.append(ov, pal);
  const renderResults = (q) => {
    const f = RESULTS.filter((r) => !q || (r[1] + ' ' + r[2]).toLowerCase().includes(q.toLowerCase()));
    let html = '', last = '';
    f.forEach((r) => {
      if (r[0] !== last) { html += `<div class="palette-group">${r[0]}</div>`; last = r[0]; }
      html += `<a class="palette-item" href="${page(r[3])}"><span class="strong">${esc(r[1])}</span><span class="muted">${esc(r[2])}</span></a>`;
    });
    return html || '<div class="empty">Nenhum resultado para essa busca.</div>';
  };
  pal.innerHTML =
    `<div class="palette-input">${svg(ICON.search, 18, 1.8)}<input type="search" placeholder="Buscar em clientes, contatos, projetos, propostas, contratos, chamados, faturas e aplicações" aria-label="Termo de busca"><span class="kbd">Esc</span></div>` +
    `<div class="palette-results" style="max-height:52vh;overflow-y:auto;padding-bottom:8px">${renderResults('')}</div>` +
    '<div class="palette-foot"><span>↑↓ navegar</span><span>Enter abrir</span><a href="' + page('busca.html') + '" style="margin-left:auto;font-weight:600">Ver todos os resultados</a></div>';
  const palInput = pal.querySelector('input');
  palInput.addEventListener('input', () => { pal.querySelector('.palette-results').innerHTML = renderResults(palInput.value); });
  const openPal = () => { pal.classList.add('open'); ov.classList.add('open'); setTimeout(() => palInput.focus(), 10); };
  const closeAll = () => {
    pal.classList.remove('open');
    document.querySelectorAll('.drawer.open, .modal.open').forEach((d) => d.classList.remove('open'));
    ov.classList.remove('open');
  };
  document.querySelectorAll('[data-search-open]').forEach((b) => b.addEventListener('click', openPal));
  ov.addEventListener('click', closeAll);
  document.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openPal(); }
    if (e.key === 'Escape') { closeAll(); body.classList.remove('nav-open'); }
  });

  /* ---------- Drawers e modais: data-open="id" / data-close ---------- */
  document.querySelectorAll('[data-open]').forEach((b) => b.addEventListener('click', (e) => {
    e.preventDefault();
    const el = document.getElementById(b.dataset.open);
    if (!el) return;
    el.classList.add('open');
    ov.classList.add('open');
    const f = el.querySelector('input, select, textarea, button');
    if (f) setTimeout(() => f.focus(), 30);
  }));
  document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', closeAll));
  document.querySelectorAll('.drawer form, .modal form').forEach((f) => f.addEventListener('submit', (e) => { e.preventDefault(); closeAll(); }));

  /* ---------- Abas: [data-tabs] > [data-tab="x"] + [data-panel="x"] ---------- */
  document.querySelectorAll('[data-tabs]').forEach((tabs) => {
    const scope = tabs.closest('[data-tabs-scope]') || document;
    tabs.querySelectorAll('[data-tab]').forEach((t) => t.addEventListener('click', () => {
      tabs.querySelectorAll('[data-tab]').forEach((x) => { x.classList.toggle('on', x === t); x.setAttribute('aria-selected', x === t); });
      scope.querySelectorAll('[data-panel]').forEach((p) => { p.hidden = p.dataset.panel !== t.dataset.tab; });
    }));
  });

  /* ---------- Filtros: [data-filter-group="tbl"] > button[data-filter] filtra [data-filter-target="tbl"] [data-status] ---------- */
  document.querySelectorAll('[data-filter-group]').forEach((grp) => {
    const target = document.querySelector(`[data-filter-target="${grp.dataset.filterGroup}"]`);
    if (!target) return;
    const rows = target.querySelectorAll('[data-status]');
    grp.querySelectorAll('button[data-filter]').forEach((b) => {
      const v = b.dataset.filter;
      const c = b.querySelector('.c');
      if (c) c.textContent = v === 'todos' ? rows.length : [...rows].filter((r) => r.dataset.status === v).length;
      b.addEventListener('click', () => {
        grp.querySelectorAll('button[data-filter]').forEach((x) => { x.classList.toggle('on', x === b); x.setAttribute('aria-pressed', x === b); });
        rows.forEach((r) => { r.hidden = v !== 'todos' && r.dataset.status !== v; });
      });
    });
  });
})();
