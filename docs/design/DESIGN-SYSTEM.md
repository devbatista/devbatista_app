# Design System — Admin DevBatista

Este documento descreve os tokens, componentes e padrões do Admin DevBatista. A implementação de referência está em [`assets/app.css`](assets/app.css) e [`assets/app.js`](assets/app.js), e todas as telas em `docs/design/` usam esses dois arquivos. Para ver um componente em uso, abra uma das telas citadas em cada seção.

A identidade vem de [devbatista.com](https://devbatista.com): tema escuro, destaque ciano e fonte Montserrat.

## Princípios

- **Escuro e calmo.** O fundo e as superfícies ficam em tons de azul-marinho. A cor aparece pouco e sempre com função: ação, seleção ou status.
- **Ciano é a ação.** O ciano marca o botão principal, links, o item ativo e o foco. Ele não é usado como cor decorativa.
- **Status sempre com texto.** Verde, amarelo e vermelho indicam estado, mas o estado também aparece escrito no badge. A cor nunca é a única pista.
- **Números alinhados.** Valores e datas usam algarismos de largura fixa (`.num` ou `.mono`) para alinhar em colunas.
- **Funciona no celular.** Toda tela precisa funcionar a partir de 360 px de largura.

## Tokens

Todos os tokens são variáveis CSS declaradas em `:root`, no topo de `app.css`. Nas telas, use sempre a variável e nunca o valor hexadecimal.

### Superfícies e bordas

| Token | Valor | Uso |
| --- | --- | --- |
| `--bg` | `#0b1120` | Fundo da página |
| `--bg-side` | `#080d1a` | Fundo do menu lateral |
| `--surface` | `rgba(15, 23, 42, .6)` | Cards, campo de busca, filtros |
| `--surface-solid` | `#0f172a` | Inputs, drawers, modais, popovers (tudo que fica por cima) |
| `--surface-2` | `#131c31` | Elementos dentro de um card: cartões do kanban, balões de mensagem |
| `--surface-hover` | `rgba(255, 255, 255, .04)` | Hover de linha de tabela e de item de menu |
| `--border` | `#1e293b` | Borda padrão de cards e inputs |
| `--border-strong` | `#334155` | Borda de botões secundários e chips |
| `--border-hover` | `rgba(8, 145, 178, .5)` | Hover de cards clicáveis |
| `--rule` | `#172033` | Divisórias internas (linhas de tabela, rodapés de card) |

### Texto

| Token | Valor | Uso |
| --- | --- | --- |
| `--white` | `#ffffff` | Títulos (`h1`, `h2`, `h3`) e valores de KPI |
| `--text` | `#f1f5f9` | Texto em destaque (`.strong`), valores em tabelas |
| `--text-2` | `#cbd5e1` | Texto corrido (cor padrão do `body`) |
| `--muted` | `#94a3b8` | Rótulos, legendas, subtítulos, cabeçalhos de tabela |
| `--faint` | `#64748b` | Placeholder e separadores da trilha |

### Destaque

| Token | Valor | Uso |
| --- | --- | --- |
| `--cyan` | `#22d3ee` | Botão principal, links, foco, item ativo, barra de dados atual |
| `--cyan-300` | `#67e8f9` | Hover do ciano, texto sobre fundo ciano translúcido |
| `--cyan-700` | `#0e7490` | Reservado |
| `--cyan-800` | `#155e75` | Séries secundárias de gráfico, etapas concluídas |
| `--cyan-tint` | `rgba(34, 211, 238, .1)` | Fundo de badge informativo, item de menu ativo, callout |
| `--cyan-line` | `rgba(22, 78, 99, .6)` | Contorno de elementos com `--cyan-tint` |
| `--blue` | `#60a5fa` | Categoria secundária (badge `.b-blue`) |
| `--orange` | `#fb923c` | Reservado |

### Status

Cada status tem três tokens: a cor do texto, um fundo translúcido (`-bg`) e um contorno (`-line`).

| Status | Texto | Fundo | Contorno | Significa |
| --- | --- | --- | --- | --- |
| Bom | `--good` `#6ee7b7` | `--good-bg` | `--good-line` | Ativo, pago, concluído, online |
| Atenção | `--warn` `#fcd34d` | `--warn-bg` | `--warn-line` | Pendente, vence em breve, rascunho em revisão |
| Crítico | `--crit` `#fca5a5` | `--crit-bg` | `--crit-line` | Vencido, inadimplente, crítico, offline |

`--crit-dot` (`#f87171`) é o vermelho sólido para pontos e barras pequenas, como o indicador de notificação e a barra de progresso crítica.

### Forma e medidas

| Token | Valor | Uso |
| --- | --- | --- |
| `--radius` | `16px` | Cards, modais, popovers |
| `--radius-sm` | `8px` | Botões, inputs, filtros, itens de menu |
| `--side-w` | `256px` | Largura do menu lateral |
| `--top-h` | `64px` | Altura da barra superior |

Outros raios usados nos componentes: `999px` para badges, chips e barras de progresso; `10px` a `12px` para cartões do kanban, callouts e avatar de empresa; `4px` para o topo das barras de gráfico.

## Tipografia

Fonte: **Montserrat** (Google Fonts), pesos 400, 500, 600 e 700. Sem internet, cai para a fonte do sistema.

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap">
```

| Estilo | Tamanho | Peso | Cor | Onde |
| --- | --- | --- | --- | --- |
| `h1` | 30 px (24 px no celular) | 700, espaçamento −0,02em | `--white` | Título da página, um por tela |
| `h2` | 16 px | 600 | `--white` | Título de card, drawer e modal |
| `h3` | 14 px | 600 | `--white` | Subtítulo dentro de card |
| Corpo | 14 px, altura de linha 1,5 | 400 | `--text-2` | Texto padrão |
| `.lead` | 14 px | 400 | `--muted` | Descrição abaixo do `h1` |
| `.section-label` | 12 px, caixa alta, espaçamento .15em | 600 | `--cyan` | Rótulo acima do `h1` (área ou contexto) |
| `.eyebrow` | 11 px, caixa alta, espaçamento .12em | 600 | `--muted` | Rótulo de KPI |
| Cabeçalho de tabela | 11 px, caixa alta, espaçamento .1em | 600 | `--muted` | `th` |
| Valor de KPI (`.kpi .v`) | 26 px (20 px no celular) | 700 | `--white` | Número em destaque |
| `.cell-sub`, `.caption` | 12 px | 400 | `--muted` | Linha secundária em célula, legenda |

Utilitários de texto: `.strong` (destaque), `.muted` (secundário), `.num` (algarismos tabulares), `.mono` (algarismos tabulares para datas e códigos), `.nowrap`, `.right`.

## Layout

Toda tela autenticada tem a mesma estrutura. O menu lateral e a barra superior são montados pelo `app.js`; a tela só deixa os elementos vazios.

```html
<body data-group="cli" data-item="Contatos" data-crumb='[["Clientes","empresas.html"],["Contatos"]]'>
<div class="app">
  <aside class="side"></aside>
  <div class="main">
    <header class="top"></header>
    <main class="content">
      <!-- conteúdo -->
    </main>
  </div>
</div>
<script src="../assets/app.js"></script>
</body>
```

- `data-group`: chave do grupo do menu (`dash`, `com`, `cli`, `op`, `fin`, `tec`, `prod`, `ges`, `adm`).
- `data-item`: rótulo do item ativo, exatamente como aparece no menu.
- `data-crumb`: trilha de navegação em JSON, `[["Rótulo","link"], ["Página atual"]]`.

`.content` tem largura máxima de 1400 px, margem de 28 × 32 px e espaço de 24 px entre blocos. Use `.content.wide` para telas que precisam de toda a largura, como o pipeline.

### Grades

| Classe | Colunas | Uso |
| --- | --- | --- |
| `.grid-kpi` | automática, mínimo 200 px | Faixa de KPIs |
| `.grid-kpi.g3` / `.g4` | 3 / 4 fixas | KPIs em quantidade conhecida, para não sobrar card sozinho na linha |
| `.grid-2` / `.grid-3` | 2 / 3 | Cards lado a lado |
| `.cols-2-1` | 2/3 + 1/3 | Telas de detalhe: conteúdo principal à esquerda, resumo à direita |
| `.stack` | 1, espaço de 16 px | Coluna de cards |
| `.row`, `.row.wrap`, `.spacer` | flex horizontal | Alinhar itens em linha |

### Espaçamento

A escala usada é 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28 e 32 px. Os valores mais comuns:

- **16 px** entre cards de uma grade.
- **24 px** entre seções da página.
- **20 px** de margem interna nos cards (`.card-body`, `.card-head`).
- **8 px** entre botões.

## Componentes

### Cabeçalho da página

```html
<div class="page-head">
  <div class="titles">
    <span class="section-label">Clientes</span>
    <h1>Contatos</h1>
    <p class="lead">Pessoas de cada empresa.</p>
  </div>
  <div class="actions">
    <button class="btn" type="button">Exportar CSV</button>
    <button class="btn pri" type="button" data-open="novo-contato">Novo contato</button>
  </div>
</div>
```

Cada tela tem no máximo um botão `.pri` no cabeçalho, para a ação principal.

### Botões

| Classe | Aparência | Quando usar |
| --- | --- | --- |
| `.btn.pri` | Fundo ciano, texto escuro | Ação principal da tela ou do formulário |
| `.btn` | Contorno cinza, fundo transparente | Ações secundárias |
| `.btn.danger` | Contorno e texto vermelhos | Ações destrutivas (cancelar contrato, excluir) |
| `.btn.sm` | 32 px de altura | Ações dentro de cards e linhas |
| `.btn.block` | Largura total | Formulários de login |
| `.link-btn` | Só texto ciano | Ações de linha em tabelas ("Editar", "Abrir →") |
| `.icon-btn` / `.icon-btn.ghost` | Quadrado de 40 px, com ou sem contorno | Ações só com ícone; sempre com `aria-label` |

A altura padrão é 40 px. Ícones dentro de botões têm 16 px e ficam antes do texto.

### Badges de status

```html
<span class="badge b-good">Ativo</span>
<span class="badge b-warn dot-l">Pendente</span>
```

| Classe | Uso |
| --- | --- |
| `.b-good` | Ativo, pago, concluído, online, aprovado |
| `.b-warn` | Pendente, próximo do vencimento, em análise, sem contrato |
| `.b-crit` | Vencido, inadimplente, crítico, cancelado, offline |
| `.b-info` | Informativo ou destaque neutro (principal, novo, programado) |
| `.b-blue` | Segunda categoria informativa, quando precisa diferenciar de `.b-info` |
| `.b-mute` | Neutro ou encerrado (rascunho, arquivado, encerrado) |

`.dot-l` acrescenta um ponto colorido antes do texto. Use-o quando o badge indica estado ao vivo, como "Ativo" no título de uma tela.

Para filtros e etiquetas que não são status, use `.chip`.

### Cards

```html
<section class="card">
  <div class="card-head"><h2>Próximos do vencimento</h2><span class="badge b-warn">3</span></div>
  <div class="card-body">…</div>
  <div class="card-foot"><span>Texto de apoio com <a href="…">link</a>.</span></div>
</section>
```

- `.card-foot` é um flex que separa o conteúdo nas pontas. Coloque texto corrido com link dentro de um `<span>`, senão ele quebra em colunas.
- `.more` é um link de largura total no rodapé ("Ver todos →").
- `a.card` ou `.card.link` deixam o card inteiro clicável, com borda ciano no hover.

### KPI

```html
<div class="grid-kpi g4">
  <div class="card kpi">
    <span class="eyebrow">MRR total</span>
    <span class="v">R$ 20.400</span>
    <span class="f"><span class="badge b-good">+8%</span> vs. agosto</span>
  </div>
</div>
```

`.kpi.warn` e `.kpi.alert` mudam a borda e o rótulo para amarelo ou vermelho. Use quando o número em si pede atenção, como contratos vencendo ou inadimplência.

### Linhas de dados

- `.kv`: linha "rótulo — valor" com divisória, para resumos na coluna lateral.
- `.dl`: grade de campos com rótulo em caixa alta, para a seção "Dados" de telas de detalhe.

```html
<div class="kv"><span>Renovação</span><b>Automática</b></div>

<dl class="dl">
  <div><dt>Número</dt><dd>#104</dd></div>
  <div><dt>Cliente</dt><dd><a href="…">Empresa ACME</a></dd></div>
</dl>
```

### Tabelas

```html
<section class="card">
  <div class="table-wrap">
    <table class="table cards" data-filter-target="contratos">
      <thead><tr><th>Número</th><th>Cliente</th><th class="num">Valor</th><th>Status</th><th><span class="sr-only">Ações</span></th></tr></thead>
      <tbody>
        <tr data-status="Ativo">
          <td data-label="Número"><a class="strong mono" href="contrato.html">#104</a></td>
          <td data-label="Cliente">Empresa ACME<span class="cell-sub">Consultoria de TI</span></td>
          <td data-label="Valor" class="num nowrap">R$ 3.000<span class="cell-sub">Mensal</span></td>
          <td data-label="Status"><span class="badge b-good">Ativo</span></td>
          <td data-label="" class="right"><a class="link-btn" href="contrato.html">Abrir →</a></td>
        </tr>
      </tbody>
    </table>
  </div>
</section>
```

- A classe `cards` transforma a tabela em cartões no celular. Cada `td` precisa de `data-label`, que vira o rótulo do cartão. A coluna de ações usa `data-label=""`.
- Valores monetários ficam alinhados à direita (`.num`) e sem quebra (`.nowrap`).
- Informação secundária vai em `.cell-sub` na mesma célula, não numa coluna a mais. **Limite prático: 7 colunas.** Acima disso a tabela estoura a largura e esconde a coluna de ações.
- Destaque de linha: `tr.late` (vencida, fundo vermelho) e `tr.soon` (vence em breve, fundo amarelo).
- `.pagination` fica abaixo da tabela, dentro do card.

### Filtros e barra de ferramentas

```html
<div class="toolbar">
  <div class="seg" role="group" aria-label="Filtrar por status" data-filter-group="contratos">
    <button type="button" class="on" data-filter="todos" aria-pressed="true">Todos <span class="n">24</span></button>
    <button type="button" data-filter="Ativo" aria-pressed="false">Ativo <span class="n">14</span></button>
  </div>
  <label class="search-field"><svg …/><input class="input" placeholder="Número, cliente ou título"></label>
  <select class="select"><option>Todos os clientes</option></select>
</div>
```

- `.seg` é o filtro de status. O botão ativo fica ciano. A contagem vai em `<span class="n">` (`.c` também funciona).
- `data-filter-group="x"` liga o filtro à tabela com `data-filter-target="x"`. Cada `tr` declara `data-status`.

### Abas

```html
<div class="tabs" role="tablist" data-tabs>
  <button class="tab on" type="button" role="tab" aria-selected="true" data-tab="resumo">Resumo</button>
  <button class="tab" type="button" role="tab" aria-selected="false" data-tab="contratos">Contratos<span class="c">2</span></button>
</div>
<section data-panel="resumo">…</section>
<section data-panel="contratos" hidden>…</section>
```

Exemplo completo: `clientes/empresa.html` (Visão 360º, 9 abas).

### Formulários

```html
<form class="form">
  <div class="fieldset-title">Dados do contato</div>
  <div class="form-grid">
    <div class="field full">
      <label for="nome">Nome <span class="req">*</span></label>
      <input class="input" id="nome" required placeholder="Nome completo">
      <span class="hint">Como aparece nas propostas</span>
    </div>
    <div class="field">
      <label for="tipo">Tipo</label>
      <select class="select" id="tipo"><option>Cliente</option></select>
    </div>
  </div>
</form>
```

- `.form-grid` tem 2 colunas (1 no celular). `.full` ocupa a linha inteira.
- Campo obrigatório: `*` em `<span class="req">`.
- `.hint` explica o campo abaixo dele.
- Outros controles: `.textarea`, `.check` (checkbox) e `.switch` (liga/desliga):

```html
<label class="switch"><input type="checkbox" checked aria-label="Renovação automática"><span></span></label>
```

### Drawer e modal

O formulário de criar e editar abre num **drawer** que entra pela direita. Confirmações curtas usam **modal**.

```html
<button class="btn pri" type="button" data-open="novo-contato">Novo contato</button>

<aside class="drawer" id="novo-contato" role="dialog" aria-modal="true" aria-labelledby="novo-contato-t">
  <div class="drawer-head">
    <h2 id="novo-contato-t">Novo contato</h2>
    <button class="icon-btn ghost" type="button" data-close aria-label="Fechar">…</button>
  </div>
  <div class="drawer-body form">…</div>
  <div class="drawer-foot">
    <button class="btn" type="button" data-close>Cancelar</button>
    <button class="btn pri" type="submit">Salvar contato</button>
  </div>
</aside>
```

O modal segue a mesma estrutura com `.modal`, `.modal-head`, `.modal-body` e `.modal-foot`. O `app.js` cria o fundo escurecido, fecha com Esc e com clique fora.

| Use | Para |
| --- | --- |
| Drawer (até 560 px) | Criar ou editar registros, formulários com mais de 3 campos |
| Modal (até 560 px) | Confirmar ação (encerrar, excluir, tornar principal), formulários de 1 a 3 campos |

O rótulo do botão de confirmação diz a ação ("Salvar contato", "Encerrar contrato"), nunca só "OK".

### Avisos

| Classe | Uso |
| --- | --- |
| `.callout` | Informação contextual em ciano |
| `.callout.warn` / `.callout.crit` | Alerta de atenção ou de problema |
| `.note` | Observação com borda tracejada, para explicar uma regra ou um limite do MVP |
| `.empty` | Estado vazio: ícone, título curto, uma frase e um botão de ação |

### Gráficos

Os gráficos são feitos em HTML e CSS, sem biblioteca.

| Classe | Uso |
| --- | --- |
| `.bars` + `.axis` | Colunas por período. `.bar.cur` destaca o período atual em ciano; os demais ficam em `--cyan-800` |
| `.hbars` / `.hbar` | Barras horizontais para ranking (rótulo, barra, valor) |
| `.progress` (`.warn`, `.crit`) | Progresso, vigência, uso de limite |
| `.legend` | Legenda com quadrados coloridos |
| `.unit` | Unidade do gráfico ("R$ mil") |

Regras: um eixo por gráfico, valores rotulados em texto e cores de status só para indicar estado, não para séries.

### Kanban

`.board` > `.lane` > `.kcard`. Cada coluna tem `.lane-head` (nome e contagem) e `.lane-sum` (total). No celular o quadro rola na horizontal. Exemplos: `comercial/pipeline.html` e `operacao/tarefas.html`.

### Outros

| Componente | Uso | Exemplo |
| --- | --- | --- |
| `.avatar` (`.sm`, `.soft`) | Iniciais de pessoa | Usuário logado, responsáveis |
| `.co-avatar` (`.sm`) | Iniciais de empresa, em quadrado arredondado | `clientes/empresas.html` |
| `.tl` | Linha do tempo de eventos | Histórico na Visão 360º |
| `.act` | Lista de atividades com hora | Dashboard |
| `.msg` (`.client`) | Conversa de chamado; mensagens do cliente em ciano | `operacao/chamado.html` |
| `.steps` / `.step` (`.done`, `.cur`) | Etapas de um fluxo | `comercial/lead.html`, `operacao/chamado.html` |
| `.chip` | Etiqueta ou filtro aplicado | Tags de serviço |
| `.divider` | Linha horizontal | Separar blocos num card |
| `.kbd` | Tecla de atalho | "⌘K" na busca |

### Elementos globais

Estes são montados pelo `app.js` em todas as telas:

- **Menu lateral:** logo, selo "Admin", grupos com submenu e usuário logado no rodapé.
- **Barra superior:** botão do menu (só no celular), trilha, busca, notificações e avatar.
- **Busca global** (`.palette`): abre com ⌘K ou Ctrl+K.
- **Notificações** (`.popover`): abre pelo sino. O ponto vermelho indica que há notificações não lidas.

## Ícones

Traço simples, no estilo [Lucide](https://lucide.dev): `viewBox="0 0 24 24"`, `fill="none"`, `stroke="currentColor"`, `stroke-width="1.8"`, pontas e junções arredondadas. Tamanhos: 20 px no menu e na barra superior, 16 px em botões e 14 px dentro de texto.

O ícone herda a cor do texto. Ícone decorativo leva `aria-hidden="true"`; botão só com ícone leva `aria-label`.

## Responsivo

| Largura | O que muda |
| --- | --- |
| até 1100 px | `.grid-3` vira 2 colunas, `.cols-2-1` vira 1 coluna, a busca encolhe |
| até 960 px | Menu vira gaveta (botão ☰), busca vira só ícone, margens de 16 px, `h1` com 24 px, grades e formulários em 1 coluna, KPIs em 2 colunas, tabelas `.cards` viram cartões |
| até 340 px | KPIs em 1 coluna |

## Acessibilidade

- Foco visível em ciano (`:focus-visible`) em todos os elementos interativos. Não remova o contorno.
- Contraste: `--text-2` e `--muted` sobre `--bg` passam AA para texto normal. `--faint` só para placeholder e separadores.
- Status nunca só por cor: o badge sempre tem o nome do estado.
- Botões só com ícone têm `aria-label`. Colunas de ação na tabela têm o cabeçalho em `.sr-only`.
- Drawers e modais têm `role="dialog"`, `aria-modal="true"` e `aria-labelledby` apontando para o título.
- Filtros `.seg` usam `aria-pressed`; abas usam `role="tab"` e `aria-selected`.

## Textos e formatos

- Português do Brasil, frases curtas e diretas. Título de tela no plural para listas ("Contratos") e no singular para detalhe ("Contrato #104").
- Botões começam com verbo: "Novo contrato", "Salvar", "Exportar CSV", "Tornar principal".
- **Moeda:** `R$ 1.200` (sem centavos quando inteiros), `R$ 1.234,56` com centavos. Recorrência como `R$ 800/mês`.
- **Datas:** `17/09/2026`. Data e hora: `17/09/2026 14:32`. Mês por extenso em cabeçalhos: "Setembro de 2026".
- **Prazos:** "vence em 30 dias", "faltam 175 dias", "venceu há 5 dias".
- **Números de registro:** `#104` para contratos, `#2394` para chamados.
- **Vazio:** `—` em células sem valor.

## Como evoluir

1. Antes de criar um estilo novo, procure um componente que já resolva. Estilo local fica no `<style>` da própria tela.
2. Se o mesmo estilo local aparecer em duas telas, mova para `app.css` e documente aqui.
3. Cores novas entram como token em `:root`, com nome pelo uso (`--warn-bg`), não pela cor.
4. Tela nova: siga a estrutura de [Layout](#layout) e registre o arquivo em `NAV` e `FOLDER` no `app.js` (veja o [README](README.md#convenções)).
