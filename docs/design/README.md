# Design — Admin DevBatista (MVP)

Protótipo navegável em HTML estático com as telas do MVP. Não precisa de build nem de servidor: abra `index.html` no navegador e navegue pelo menu.

## Estrutura

Cada item principal do menu é uma pasta. As telas de detalhe ficam na pasta da listagem de onde se chega a elas.

```
docs/design/
├── index.html            catálogo de todas as telas, agrupadas por área
├── DESIGN-SYSTEM.md      tokens, componentes e regras de uso
├── assets/
│   ├── app.css           identidade visual e todos os componentes
│   ├── app.js            menu, barra superior, busca, notificações e interações
│   ├── wa-iniciar.js     diálogo "Iniciar conversa no WhatsApp" (lead, empresa e contato)
│   └── logo-*.png        logo DevBatista em branco (completo e só o ícone)
├── dashboard/            dashboard executivo
├── comercial/            leads, lead, oportunidades, propostas, proposta, pipeline
├── whatsapp/             conversas, templates e conexão (esta fica no menu em Tecnologia → Integrações); regras no README da pasta
├── clientes/             empresas, empresa (Visão 360º), contatos, contratos, contrato, serviços contratados
├── operacao/             projetos, projeto, tarefas, chamados, chamado, horas
├── financeiro/           dashboard financeiro, receitas, despesas, contas a receber e a pagar, recorrências, notas fiscais
├── tecnologia/           aplicações, aplicação, servidores, domínios, bancos de dados, integrações, serviços externos
├── produtos/             produtos próprios, assinaturas, indicadores dos produtos
├── gestao/               fornecedores, documentos, relatórios, indicadores, rentabilidade
├── administracao/        usuários, permissões, logs, configurações, catálogo de serviços
├── acesso/               login e recuperação de senha (fora do menu)
└── geral/                central de notificações e resultados da busca (fora do menu)
```

## Identidade visual

Segue [devbatista.com](https://devbatista.com):

- **Tema escuro:** fundo `#0B1120`, cards translúcidos com borda `#1E293B` e cantos de 16 px.
- **Destaque:** ciano `#22D3EE`. O botão principal é ciano com texto escuro.
- **Fonte:** Montserrat, vinda do Google Fonts. Sem internet, as telas usam a fonte do sistema.
- **Status:** verde para ativo e pago, amarelo para pendente e atenção, vermelho para vencido e crítico, ciano para informativo, cinza para neutro.

As cores e medidas ficam como variáveis no topo de `assets/app.css`. Tokens, componentes e regras de uso estão em [DESIGN-SYSTEM.md](DESIGN-SYSTEM.md).

## Convenções

- Cada tela declara no `<body>` o grupo e o item ativos do menu (`data-group`, `data-item`) e a trilha de navegação (`data-crumb`). O `app.js` monta o menu lateral e a barra superior a partir disso.
- O menu e a pasta de cada tela ficam nas constantes `NAV` e `FOLDER` de `assets/app.js`. Para criar uma tela nova, adicione o arquivo na pasta certa e registre o nome nas duas constantes.
- Interações prontas, sem JavaScript na página:
  - `data-open="id"` e `data-close` abrem e fecham formulários laterais (`.drawer`) e modais (`.modal`).
  - `data-tabs`, `data-tab` e `data-panel` criam abas.
  - `data-filter-group`, `data-filter`, `data-filter-target` e `data-status` filtram linhas por status.
  - `data-proto-scope`, `data-proto-state` e `data-proto-view` alternam variações de um card (seletor tracejado `.proto-switch`). Só existem no protótipo.
- Busca global com ⌘K / Ctrl+K em todas as telas.
- No celular (até 960 px) o menu vira gaveta, as tabelas com a classe `cards` viram cartões e os quadros kanban rolam na horizontal.

## Dados

Os dados são ilustrativos e coerentes entre as telas. Por exemplo, a Empresa ACME, a Empresa XYZ, o contrato #104 e o chamado crítico #2394 aparecem com os mesmos valores onde se repetem. "Hoje" é 17/09/2026.

As specs funcionais ficam em [`../specs/admin-devbatista-mvp/`](../specs/admin-devbatista-mvp/README.md).
