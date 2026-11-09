# Visitas do site — v1

Novembro de 2026 · Área do Admin para acompanhar as visitas ao site devbatista.com. A coleta é própria: o site manda cada página vista ao Admin, que guarda as visitas no Postgres, sem cookie e sem guardar IP. Na v1 a tela mostra só a visão geral; a origem do tráfego, as páginas e o funil até o lead vêm depois, sobre os mesmos dados.

## Decisões

| Tema | Decisão |
| --- | --- |
| Fonte dos dados | **Coleta própria no Admin.** Hoje o site só tem o Pixel da Meta (que continua), e não há histórico em lugar nenhum: a contagem começa no dia em que o script entrar no ar |
| Caminho da coleta | Navegador → `POST devbatista.com/api/v.php` (o PHP do próprio site) → `POST admin.devbatista.com/webhooks/site-visits`, servidor a servidor, com `SITE_VISITS_TOKEN`. É o mesmo padrão do `/webhooks/site-leads`. O token não vai para o navegador, a chamada fica no mesmo domínio (sem CORS e menos bloqueio por adblock) e o PHP repassa o IP real do visitante |
| Identificação do visitante | **Sem cookie nem `localStorage`.** O Admin calcula um hash do sal do dia, do IP e do user agent e descarta o IP. O sal muda à meia-noite e o do dia anterior é apagado, então o mesmo visitante não é reconhecido de um dia para o outro |
| Visita (sessão) | Páginas vistas pelo mesmo visitante com no máximo 30 min entre uma e outra. Passou disso, abre uma visita nova |
| Robôs | Fora da contagem de visitas: user agent de bot, crawler ou navegador headless, e as requisições de prefetch. Os de IA são registrados à parte, como acessos de IA; os outros são descartados |
| Acessos de IA | Captados **no servidor do site, pelos headers da requisição**, já que robô de IA não roda JavaScript e o script nunca o vê. O PHP só repassa os headers; quem classifica é o Admin, por um catálogo de agentes em `config/ai_agents.yml`, que muda sem mexer no site |
| Origem | Toda visita recebe um **canal** na entrada (Assistentes de IA, Campanha, E-mail, Busca, Redes sociais, Outros sites, Direto), além da referência e da UTM |
| Escopo da v1 | Coleta completa e tela de visão geral. A origem (referência e UTM), o dispositivo e a página de entrada já são gravados desde o primeiro dia, porque não dá para recuperar depois, mas só aparecem na tela nas próximas fases |
| Menu | Grupo novo **Marketing**, item **Visitas do site** (`/marketing/site-visits`) |
| Usuários | Área nova `marketing` na matriz de permissões. Administrador "full"; os outros perfis começam sem acesso |
| Análise pelo Claude | Três tools de leitura no MCP do Admin (`visitas_resumo`, `visitas_por_dimensao` e `acessos_ia`). Elas usam o mesmo cálculo da tela (`SiteVisits::Stats`), então o Claude e a tela nunca divergem. O Claude recebe só números agregados, nunca visitas individuais nem `visitor_hash` |
| Fora da v1 | Na tela: origem do tráfego, páginas, funil até o lead, "agora no site", país, eventos personalizados, exportação. A origem e as páginas já podem ser analisadas pelo Claude desde a v1 |

## Coleta

### No site (PHP)

O site é HTML estático num Apache compartilhado (deploy por FTP). O PHP só existe em `api/`, então as páginas não podem incluir PHP: os robôs chegam ao PHP por uma regra do `.htaccess`.

**Script** (`/js/visitas.js`, carregado com `defer` em todas as páginas, menos a `servicos.html`, que só redireciona):
- Na carga da página, manda um evento `pageview` com um `id` gerado no navegador (`crypto.randomUUID()`), a URL, o `document.referrer` e a largura da tela.
- Na saída (`pagehide`, ou `visibilitychange` para `hidden`), manda um evento `leave` com o mesmo `id` e o tempo em que a página ficou visível, em ms. Só vai um `leave` por página.
- Envia com `navigator.sendBeacon('/api/v.php', json)`, com `fetch(..., { keepalive: true })` como alternativa. O envio nunca trava nem quebra a página.
- Não conta a visita quando `localStorage.devbatista_nao_contar === "1"`. O valor é gravado ao abrir qualquer página com `?nao-contar=1` (e apagado com `?nao-contar=0`), para o Rafael não inflar os próprios números. Também não conta com `navigator.webdriver` (automação declarada).
- Voltar pelo botão do navegador (bfcache) conta como página vista nova. Página pré-renderizada só conta quando é de fato aberta (`prerenderingchange`).

**Proxy** (`api/v.php`):
- Aceita só `POST`, com corpo de até 4 KB. Recusa com 403 um `Origin` fora de `allowed_origins`. Responde `204` na hora e usa `fastcgi_finish_request()` (ou `litespeed_finish_request()`) para o repasse não segurar o navegador.
- Do corpo, repassa só os campos do script (`type`, `id`, `url`, `referrer`, `screen_width`, `duration_ms`), mais o `ip` e os `headers` da lista abaixo, com `Authorization: Bearer SITE_VISITS_TOKEN` e timeout de 2 s. O navegador não consegue mandar IP nem headers próprios.
- O IP é só o `REMOTE_ADDR`. O site não está atrás da Cloudflare, então um `CF-Connecting-IP` viria do próprio cliente, e um robô falso poderia usá-lo para se passar por um IP oficial.
- Falha no repasse só vai para o log. Sem fila nem nova tentativa: perder uma página vista é aceitável.

**Captura no servidor** (regra 3b do `.htaccess` + `api/agente.php`):
- O `.htaccess` manda ao `api/agente.php` só as requisições `GET`/`HEAD` de página com cara de robô ou de agente: header `Signature-Agent`, ou user agent com `bot`, `crawl`, `spider`, `-User`, `GPT`, `Claude`, `Perplexity`, `anthropic`, `openai`, `meta-external` ou `MistralAI`. Os buscadores comuns (Googlebot, Bingbot, Yandex, Baidu, DuckDuckBot) ficam de fora, para o SEO nunca depender do PHP. Pessoas recebem o HTML estático direto, como sempre.
- O `api/agente.php` entrega o mesmo HTML que o Apache entregaria (com `Last-Modified` e `304`) e, depois de responder, manda ao Admin um `server_hit` com a URL, o IP e os headers. Só para página que existe e só no `GET`. Qualquer falha no aviso é engolida: a página já foi entregue.
- A peneira do `.htaccess` é larga de propósito. Quem classifica é o Admin, pelo catálogo, e um robô que não é de IA é descartado lá. Um agente de IA novo só precisa entrar no `.htaccess` se o user agent dele não tiver nenhum dos termos da peneira.

**Headers repassados** (`api/visitas.php`), os mesmos no proxy e na captura no servidor: `User-Agent`, `Referer`, `Accept`, `Accept-Language`, `From`, `Signature-Agent`, `Signature-Input`, `Signature`, `Sec-Fetch-Mode`, `Sec-Fetch-Site`, `Sec-CH-UA`, `Sec-Purpose` e `Purpose`. Nunca vai cookie nem header de autenticação.

### No Admin

`POST /webhooks/site-visits` (`Webhooks::SiteVisitsController < ActionController::API`, fora do login, do Pundit e do CSRF, como o de leads).

```json
{
  "type": "pageview",
  "id": "3f1c…",
  "url": "https://devbatista.com/servicos?utm_source=instagram&utm_campaign=nov",
  "referrer": "https://www.instagram.com/",
  "screen_width": 390,
  "duration_ms": null,
  "ip": "200.1.2.3",
  "headers": {
    "user-agent": "Mozilla/5.0 …",
    "accept-language": "pt-BR,pt;q=0.9",
    "sec-fetch-mode": "cors"
  }
}
```

`type`: `pageview` e `leave` vêm do script; `server_hit` vem da captura no servidor (sem `id`, `screen_width` nem `duration_ms`).

| Resposta | Quando |
| --- | --- |
| `202` | Evento aceito ou descartado de propósito (robô, host de fora, `leave` sem `pageview`). O site não precisa saber a diferença |
| `401` | Token errado ou `SITE_VISITS_TOKEN` não configurado (registra no log, como o de leads) |
| `422` | JSON inválido, `type` desconhecido, `id` ou `url` ausentes |

O serviço `SiteVisits::Tracker` faz o resto, na própria requisição (é só um insert e um update, sem job):
1. Descarta se o host da `url` não for `devbatista.com` ou `www.devbatista.com` (`config.x.site_visits.hosts`; em desenvolvimento, `SITE_VISITS_HOSTS` acrescenta o local). Passa os headers pelo `SiteVisits::AiAgentClassifier` (seção Acessos de IA): se for agente de IA, grava um acesso de IA e para por aí. Se for outro robô, descarta. Um `server_hit` de navegador comum também é descartado, porque quem conta essa visita é o script.
2. Calcula `visitor_hash = SHA-256(sal do dia + ip + user_agent)`, truncado em 16 caracteres hex. O IP não é gravado em lugar nenhum nem vai para o log.
3. **`pageview`**: procura a última visita desse `visitor_hash` com `last_seen_at` nos últimos 30 min. Se achar, soma a página a ela (`pageviews_count`, `last_seen_at`, `exit_path`); se não, abre uma visita nova com a página de entrada, a referência, a UTM e o dispositivo. Grava a página vista com o `id` do navegador. `id` repetido é ignorado: o insert é idempotente.
4. **`leave`**: grava `duration_seconds` na página vista com aquele `id` (até 30 min, para uma aba esquecida aberta não distorcer a média) e recalcula a duração da visita. `leave` repetido não soma de novo.
5. Da URL fica só o caminho, sem barra no fim, e os cinco parâmetros de UTM em colunas próprias. O resto da query é descartado: pode conter e-mail ou token.
6. Prefetch e prerender do navegador (`Sec-Purpose`/`Purpose: prefetch`) são descartados.

**Sal do dia:** tabela `site_visit_salts`, com `day` e `salt` (32 bytes aleatórios), criado na primeira visita de cada dia, no fuso do app. O job `SiteVisitSaltCleanupJob` roda à 00:10 (`config/schedule.yml`) e apaga os sais anteriores a hoje. O sal não é derivado do `secret_key_base` nem de nada fixo: se fosse, daria para reconstruir o hash testando todos os IPs.

**Dispositivo:** pela largura da tela (`mobile` < 768 px, `tablet` < 1024 px, `desktop` acima disso); sem largura, pelo user agent. O navegador e o sistema saem do user agent, por um parser simples feito no projeto, sem gem nova.

**Referência:** grava só o host (`www.google.com` → `google.com`). Referência do próprio site conta como vazia, e a visita entra como direta.

**Canal**, calculado na abertura da visita. Vale a primeira regra que bater:

| Canal | Regra |
| --- | --- |
| Assistentes de IA | Referência ou `utm_source` de um assistente do catálogo (`chatgpt.com`, `perplexity.ai`, `claude.ai`, `gemini.google.com`, `copilot.microsoft.com`, `meta.ai`, `chat.deepseek.com`, `grok.com`, `chat.mistral.ai`…). O ChatGPT põe `utm_source=chatgpt.com` nos links que mostra. Grava também qual assistente foi, em `ai_assistant` |
| E-mail | `utm_medium=email`, ou referência de webmail (`mail.google.com`, `outlook.live.com`…) |
| Campanha | Qualquer outra UTM |
| Busca | Referência de buscador (Google, Bing, DuckDuckGo, Yahoo, Ecosia, Yandex) |
| Redes sociais | Referência de rede (Instagram, Facebook, LinkedIn, X/`t.co`, YouTube, TikTok, WhatsApp, Threads) |
| Outros sites | Qualquer outra referência |
| Direto | Sem referência e sem UTM |

Visita vinda de um app de IA no celular costuma chegar sem referência e entra como Direto. Então o canal Assistentes de IA mostra um piso, não o total.

## Acessos de IA

Robôs e agentes de IA que buscam páginas do site. Não são visitas de pessoas e não entram em nenhum indicador de visitas.

**Sinais nos headers**, do mais confiável ao mais fraco:

| Sinal | Onde | Confiança |
| --- | --- | --- |
| Assinatura do agente (Web Bot Auth, HTTP Message Signatures, RFC 9421) | `Signature-Agent` (o domínio do agente), `Signature-Input` e `Signature` | Alta quando conferida com a chave pública que o agente publica em `/.well-known/http-message-signatures-directory`. O agente do ChatGPT já assina assim, e outros estão adotando |
| User agent declarado com IP nas faixas oficiais | `User-Agent` + IP | Alta. A OpenAI e a Perplexity, por exemplo, publicam as faixas de IP dos seus robôs |
| Só o user agent declarado | `User-Agent` | Média: qualquer um pode escrever "GPTBot" no user agent |
| Pede Markdown | `Accept: text/markdown` | Fraca. Só fica registrado, não classifica nada sozinho |

**Catálogo** (`config/ai_agents.yml`): para cada agente, o padrão do user agent, o nome, a empresa, o tipo e, quando houver, a URL das faixas de IP. Lista inicial:

| Tipo | Agentes |
| --- | --- |
| `training` Treino | GPTBot (OpenAI), ClaudeBot e anthropic-ai (Anthropic), CCBot (Common Crawl), Meta-ExternalAgent e FacebookBot (Meta), Bytespider (ByteDance), Amazonbot (Amazon), Applebot (Apple), cohere-training-data-crawler (Cohere), AI2Bot (Ai2), Diffbot, ImagesiftBot, Omgilibot (Webz.io), Timpibot, PanguBot (Huawei) |
| `search` Busca com IA | OAI-SearchBot (OpenAI), Claude-SearchBot (Anthropic), PerplexityBot (Perplexity), DuckAssistBot (DuckDuckGo), YouBot (You.com) |
| `user` A pedido de alguém | ChatGPT-User (OpenAI), Claude-User e Claude-Web (Anthropic), Perplexity-User (Perplexity), Meta-ExternalFetcher (Meta), MistralAI-User (Mistral), cohere-ai (Cohere) |

**Bloqueados.** O `.htaccess` do site já barrava com 403 os robôs de treino (regra 0a: GPTBot, ClaudeBot, anthropic-ai, CCBot, Bytespider, Amazonbot, Meta, Cohere, Diffbot e outros). O bloqueio continua igual, mas os pedidos de página desses robôs passam pelo `api/agente.php`, que responde o mesmo 403 e manda o `server_hit` com `blocked: true`. O acesso entra com `ai_hits.blocked`: a tentativa conta, a página não foi entregue. Imagens, CSS e arquivos continuam barrados direto pelo Apache, sem contar. Todos os robôs da regra 0a estão no catálogo, para nenhuma tentativa ser descartada como robô desconhecido.
| `agent` Navegação autônoma | Requisições assinadas com `Signature-Agent` (ex.: `https://chatgpt.com`) |

O tipo `user` é o sinal mais útil: alguém perguntou algo a uma IA e ela abriu a página do site para responder. A lista muda com frequência e deve ser revista a cada poucos meses.

**Verificação**, gravada em cada acesso:

| Valor | Quando |
| --- | --- |
| `signed` Assinado | Veio com `Signature-Agent`. Na v1, a assinatura não é conferida, só registrada |
| `ip_verified` IP confirmado | User agent do catálogo e IP dentro das faixas oficiais |
| `declared` Declarado | User agent do catálogo, e a empresa não publica faixas de IP |
| `spoofed` Falso | User agent do catálogo, mas IP fora das faixas publicadas. Aparece separado e não entra nos totais |

- O job `AiAgentIpRangesJob` roda uma vez por dia (`config/schedule.yml`), baixa as faixas de IP publicadas e guarda no cache. Se o download falhar, mantém as faixas anteriores.
- O IP serve só para a verificação. Não é gravado nem no acesso de IA.

**O que a captura não alcança:**
- **IA do Google.** O Gemini e as AI Overviews usam o próprio Googlebot, e `Google-Extended` é só uma regra do `robots.txt`, não aparece nos headers. Não dá para separar da indexação comum do Google.
- **`Applebot-Extended`** também é só uma regra do `robots.txt`. O Applebot entra como Treino, mesmo quando é a busca da Apple.
- **Navegadores com IA** (ChatGPT Atlas, Comet e parecidos) usam o motor do Chrome e não mandam assinatura. Aparecem como pessoa comum, e a visita é contada pelo script.
- **`robots.txt`, `sitemap.xml` e `llms.txt`** são arquivos estáticos do Apache e não passam pelo PHP. Contar quem os lê fica para a fase 3, com uma regra no `.htaccess` que os sirva por PHP.

## Modelo de dados

| Tabela | Conteúdo |
| --- | --- |
| `site_visits` | `visitor_hash`, `started_at`, `last_seen_at`, `pageviews_count`, `duration_seconds`, `entry_path`, `exit_path`, `referrer_host`, `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term`, `channel`, `ai_assistant`, `device_type`, `browser`, `os` |
| `site_pageviews` | `site_visit_id`, `client_id` (o `id` do navegador, único), `path`, `occurred_at`, `duration_seconds` |
| `ai_hits` | `agent` (a chave do catálogo, ou `signed:<domínio>`), `agent_name` e `company` (copiados do catálogo na hora, para o histórico não mudar com ele), `kind`, `verification`, `signature_agent`, `path`, `accepts_markdown`, `blocked` (barrado pelo `.htaccess` do site), `occurred_at` |
| `site_visit_salts` | `day` (único), `salt` |

**Regras:**
- `device_type` com `labeled_enum`: `desktop` Computador · `mobile` Celular · `tablet` Tablet.
- `channel` com `labeled_enum`: `ai_assistant` Assistentes de IA · `email` E-mail · `campaign` Campanha · `search` Busca · `social` Redes sociais · `referral` Outros sites · `direct` Direto.
- `ai_hits.kind` e `ai_hits.verification` com `labeled_enum`, com os valores da seção Acessos de IA. Índice em `ai_hits (occurred_at)`.
- Índices: `site_visits (visitor_hash, last_seen_at DESC)` para achar a visita aberta; `site_visits (started_at)` para os números do período; `site_pageviews (client_id)` único; `site_pageviews (site_visit_id)`.
- Sem `Auditable`: são dados de máquina, em volume, e não ações de usuário.
- Caminho até 500 caracteres e campos de UTM até 200; o que passar disso é cortado, não recusado.

## Tela (v1)

**Menu:** grupo novo **Marketing** (`NavigationHelper::NAV`, chave `:mkt`, ícone próprio), com o item **Visitas do site** (área `marketing`). Os próximos itens do grupo, como campanhas, entram aqui.

**Visitas do site** (`/marketing/site-visits`, `Marketing::SiteVisitsController#index`):

- **Período** no topo (`?periodo=`): Hoje, Ontem, Últimos 7 dias (padrão), Últimos 30 dias, Este mês, Mês passado e Últimos 12 meses. Concern próprio, no estilo do `FinancePeriod`. O período anterior, para comparar, tem o mesmo tamanho e termina onde o atual começa.
- **Indicadores** (`grid-kpi`, um card por número, com o `variation_badge` em relação ao período anterior):

| Card | Cálculo |
| --- | --- |
| Visitantes únicos | Soma, dia a dia, dos `visitor_hash` distintos (como o sal muda todo dia, o mesmo visitante em dois dias conta duas vezes; a nota do card diz isso) |
| Visitas | Visitas iniciadas no período |
| Páginas vistas | Páginas vistas no período |
| Páginas por visita | Páginas vistas ÷ visitas |
| Taxa de rejeição | Visitas com uma página só e menos de 10 s ÷ visitas (o `variation_badge` com `inverse: true`: subir é ruim) |
| Duração média | Média de `duration_seconds` das visitas, em "2 min 15 s" |

- **Gráfico** de visitantes e visitas por dia (por hora em Hoje e Ontem; por mês em Últimos 12 meses), com dias sem visita como zero. Helper novo em `ChartsHelper`, em SVG desenhado no servidor como os gráficos mensais de hoje. Sem biblioteca de gráfico.
- **Sem dados ainda:** antes da primeira visita, a tela mostra o `shared/_empty` com o passo a passo para instalar o script no site.
- Os números do período saem do serviço `SiteVisits::Stats` (período, filtros, indicadores, série e agrupamentos), com consultas agregadas direto em `site_visits` e `site_pageviews`. A tela e as tools do MCP só formatam o que ele devolve. Cache de 15 min (o limite do dashboard nos requisitos não funcionais); Hoje e Ontem ficam sem cache.

**Permissões:** área `marketing` em `Role::AREAS` ("Marketing"), com o Administrador em "full". `SiteVisitPolicy#index?` exige leitura na área, tanto na tela quanto no MCP.

## Tools do MCP

No padrão do [MCP do Admin](../mcp-comercial/README.md): `Mcp::Tools::Base`, `read_only`, `authorize(:site_visit, :index?)`, respostas em JSON com chaves em português e datas em AAAA-MM-DD, no fuso do app.

**Período**, igual nas duas tools: `periodo` aceita as mesmas opções da tela (`hoje`, `ontem`, `7d` (padrão), `30d`, `este_mes`, `mes_passado`, `12m`), ou `de` e `ate` (AAAA-MM-DD) para um intervalo livre de até 400 dias. Com `de`/`ate`, o `periodo` é ignorado. A resposta sempre devolve as datas usadas e o período anterior comparado.

**Filtros**, iguais nas duas tools, todos opcionais e combináveis. Valem para a visita inteira: `pagina` filtra as visitas que passaram pela página.

| Filtro | Exemplo |
| --- | --- |
| `canal` | `ai_assistant`, `search`, `social`, `campaign`, `email`, `referral`, `direct` |
| `origem` | `google.com`, `instagram.com`, `chatgpt.com` ou `direto` |
| `utm_source`, `utm_medium`, `utm_campaign` | `instagram`, `cpc`, `nov-diagnostico` |
| `pagina` | `/servicos` (caminho exato) |
| `pagina_entrada` | `/` |
| `dispositivo` | `desktop`, `mobile`, `tablet` |

| Tool | O que faz |
| --- | --- |
| `visitas_resumo` | Os seis indicadores da tela (visitantes únicos, visitas, páginas vistas, páginas por visita, taxa de rejeição em %, duração média em segundos), o valor no período anterior e a variação em %. Traz também a série por dia (por hora em `hoje`/`ontem`, por mês em `12m`), com zero nos dias sem visita, e a data da primeira visita registrada, para o Claude saber quando os dados começam |
| `acessos_ia` | Acessos de robôs e agentes de IA no período, agrupados por `agrupar` (`empresa` (padrão), `agente`, `tipo`, `pagina` ou `dia`), com o total por tipo e por verificação, separando os servidos dos bloqueados pelo site. Os falsos ficam fora dos totais e aparecem numa contagem à parte. Para comparar, traz também as visitas de pessoas do canal Assistentes de IA no mesmo período (quem a IA leu × quem a IA mandou). Filtros: `empresa`, `tipo`, `verificacao`, `pagina` |
| `visitas_por_dimensao` | Agrupa o período por `dimensao`: `canal`, `assistente_ia`, `origem`, `utm_source`, `utm_medium`, `utm_campaign`, `pagina`, `pagina_entrada`, `pagina_saida`, `dispositivo`, `navegador`, `sistema`, `dia_da_semana` ou `hora`. Cada linha traz visitantes, visitas, páginas vistas, % do total, taxa de rejeição e duração média, ordenada por visitas, até `limite` linhas (padrão 25, até 50), mais o total fora das linhas devolvidas ("outros") |

**Exemplo:** "o Instagram trouxe mais gente esse mês?" vira `visitas_resumo(periodo: "este_mes", origem: "instagram.com")`. "Que páginas quem vem do Google mais vê?" vira `visitas_por_dimensao(dimensao: "pagina", origem: "google.com")`. "Que IAs estão lendo o site, e quais páginas?" vira `acessos_ia(periodo: "30d", agrupar: "pagina", tipo: "user")`.

**Regras:**
- Agrupamento com menos de 3 visitantes únicos no período aparece com os números, mas sem o rótulo de UTM ou de caminho que vier com query. Assim um link enviado a uma pessoa só (com UTM própria) não identifica quem visitou.
- Sem tool de escrita: o MCP não apaga nem altera visitas.
- `Mcp::Endpoint::TOOLS` recebe as três tools, e o texto de `INSTRUCTIONS` passa a citar as visitas do site: os números são agregados, o visitante único é contado por dia, a contagem só existe a partir da data de `primeira_visita`, e acesso de IA não é visita de pessoa.
- A agente Mia (Marketing) do [Escritório](../escritorio-agentes/README.md) pode usar as duas tools numa rotina (um resumo semanal com `registrar_evento`, por exemplo). A rotina em si fica fora desta spec.

## Configuração

| Variável | Onde | Uso |
| --- | --- | --- |
| `SITE_VISITS_TOKEN` | Admin e PHP do site | Token do repasse (`config.x.site_visits.token`). Separado do `SITE_LEADS_TOKEN`: quem vazar um não grava no outro |
| `SITE_VISITS_ADMIN_URL` | PHP do site | `https://admin.devbatista.com/webhooks/site-visits` |

## Fases

1. ✅ **Coleta**: tabelas, `SiteVisits::Tracker`, webhook, sal do dia e job de limpeza, filtro de robôs, `SiteVisits::UserAgent`, `SiteVisits::Channel`, `SiteVisits::AiAgentClassifier` com o catálogo, `SiteVisits::AiAgentIpRanges` e o `AiAgentIpRangesJob`, script, proxy e captura no servidor do site, `SITE_VISITS_TOKEN`. Fica coletando enquanto a tela é feita.
2. **Visão geral e MCP**: `SiteVisits::Stats`, área `marketing`, policy, as tools `visitas_resumo`, `visitas_por_dimensao` e `acessos_ia`, grupo Marketing, período, indicadores, gráfico, estado vazio, seeds de visitas fora de produção. As tools podem ir para produção antes da tela, já que usam o mesmo serviço.
3. **Próximas** (cada uma é uma seção nova na mesma tela, sem coleta nova): acessos de IA, conferência criptográfica da assinatura do Web Bot Auth (Ed25519), contagem de `robots.txt`, `sitemap.xml` e `llms.txt` via `.htaccess`, origem do tráfego (canal, referência e UTM), páginas (mais vistas, de entrada e de saída), dispositivos e o funil visita → quiz → lead. O funil exige o `site_visit` no payload do `/webhooks/site-leads`, e quando existir entra no MCP como a dimensão `convertidas` ou como a tool `visitas_funil`.

## Testes

Fase 1: `spec/services/site_visits_tracker_spec.rb` (visita nova ou existente pela janela de 30 min, idempotência do `id`, `leave` sem `pageview`, robô, prefetch, host de fora, limpeza da query, teto de duração, IP fora do banco, beacon de agente ignorado), `spec/services/site_visits_classification_spec.rb` (canal e a ordem das regras, `utm_source=chatgpt.com`; dispositivo, navegador, sistema e robô; agentes do catálogo, assinado, IP confirmado, declarado, falso, navegador comum, robô fora do catálogo, faixas indisponíveis, Redis fora do ar; download das faixas), `spec/requests/site_visits_webhook_spec.rb` (202, 401, 422, `server_hit` de IA grava acesso) e `spec/jobs/site_visit_jobs_spec.rb` (sal e faixas). Fase 2: `spec/services/site_visits_stats_spec.rb` (cada indicador, visitante único somado por dia, período anterior, filtros combinados, cada dimensão, "outros", ocultação abaixo de 3 visitantes), `spec/services/mcp/tools_visitas_spec.rb` (as três tools, falsos fora dos totais, período por opção e por `de`/`ate`, intervalo acima de 400 dias, dimensão inválida, limite, mesmos números da tela, permissão negada), `spec/requests/marketing/site_visits_spec.rb` (indicadores por período, comparação, estado vazio, menu e 403) e `spec/policies/site_visit_policy_spec.rb`. O script e o proxy do site são conferidos à mão, nas ferramentas do navegador, depois do deploy.

## Pontos em aberto

- **País e cidade.** Sem IP guardado, só dá para saber o país na entrada. Se o site estiver atrás da Cloudflare, o cabeçalho `CF-IPCountry` resolve sem custo; se não, precisa de uma base GeoIP. Fica para a fase 3.
- **Retenção.** Sem limite na v1. Com o volume de um site institucional, as tabelas ficam pequenas por anos. Avaliar uma tabela diária agregada se as consultas passarem de 1 s.
- **Robôs que se passam por navegador.** O filtro por user agent não pega tudo. Se um pico estranho aparecer, avaliar um limite por `visitor_hash` por minuto.
- **Política de privacidade do site.** A coleta não usa cookie nem guarda IP, mas vale citar na política do site que há medição de audiência própria e anônima.
