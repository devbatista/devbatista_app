# MCP do Admin DevBatista — v1 (Comercial)

Outubro de 2026 · Servidor MCP (Model Context Protocol) dentro do próprio app, para o Admin DevBatista virar um **conector do Claude** (claude.ai, Desktop, celular e Claude Code).

## Decisões

| Tema | Decisão |
| --- | --- |
| Áreas na v1 | Só **Comercial**: leads, pipeline, oportunidades, propostas e interações |
| Escrita | Leitura + criação e alteração. **Sem exclusão**, sem mexer em dinheiro. Para fora, só o texto de WhatsApp a lead (`enviar_whatsapp`), com aprovação a cada envio; proposta continua sem envio pelo MCP |
| Autenticação | **OAuth 2.1** (Doorkeeper) já na v1, para funcionar como conector no claude.ai |
| Usuários | Só o administrador. A tela de autorização recusa outros perfis |
| Auditoria | As ações pelo MCP gravam `ip_address` como `mcp:<ip>` no `AuditLog`, para separar o que veio do Claude |

## Princípio

Cada chamada de tool roda **como um usuário real**: o token resolve o `User`, que vai para `Current.user`, e a tool usa `authorize`/`policy_scope` do Pundit como os controllers. O Claude nunca vê nem faz mais do que esse usuário faria pela tela, e toda escrita passa pelos models (validações, `AuditLog` e `Activity`).

## Tools

### Auxiliares (leitura)

| Tool | O que faz |
| --- | --- |
| `opcoes_comerciais` | Origens, status de lead, etapas de oportunidade, tipos de interação, motivos de perda, serviços do catálogo e usuários ativos. O Claude consulta antes de escrever |
| `buscar_empresas` | Busca empresas por nome (a oportunidade exige empresa) |

### Leitura

| Tool | O que faz |
| --- | --- |
| `buscar_leads` | Filtros: termo, status, origem, responsável, só abertos e `com_resposta_whatsapp_desde` (abaixo) |
| `ver_lead` | Dados, interações, oportunidades e propostas. Com leitura na área WhatsApp: `janela_whatsapp_aberta_ate` no topo (quando a janela de 24h está aberta) e, em cada interação "Conversa do dia", as `mensagens` daquele dia no formato do `ver_conversa_whatsapp` (as 30 mais recentes do lead, somando os dias; `mensagens_omitidas` conta as do dia que ficaram de fora) |
| `ver_conversa_whatsapp` | Mensagens do WhatsApp do lead em ordem cronológica e a janela de 24h (abaixo). Exige leitura na área WhatsApp |
| `pipeline` | Leads e oportunidades por etapa, com quantidade e valor estimado |
| `proximos_passos` | Mesma lista da tela Comercial → Próximos passos: leads e oportunidades em aberto pela data e hora do próximo passo, do mais antigo ao mais novo. Parâmetros: `de`/`ate` (só a data = o dia inteiro), `incluir_atrasados` (padrão true, entram mesmo antes de `de`), `incluir_sem_data` (padrão false), `tipo` (lead/oportunidade/todos) e `limite` (padrão 50, até 200). Cada item: `tipo`, `id`, `nome`, `empresa`, `acao`, `quando` (ISO 8601, -03:00), `atrasado`, `grupo`, `status`, `whatsapp`, `link` e `ultima_interacao` (data, tipo e texto curto). As instruções do servidor pedem para chamar no começo de cada sessão comercial |
| `buscar_oportunidades` / `ver_oportunidade` | Lista e detalhe |
| `buscar_propostas` / `ver_proposta` | Itens, total, validade e status |

Leitura do WhatsApp (`Mcp::Tools::WhatsappData` dá o formato às duas tools):

- **Fonte**: as `WhatsappMessage` que o webhook já grava (recebidas, ecos do app do celular, enviadas pelo Admin e o histórico), com direção, tipo, texto ou legenda, horário e wamid. A interação automática do dia continua só com as contagens.
- **`ver_conversa_whatsapp`** (`lead_id`, `desde` AAAA-MM-DD, `limite` padrão 30, até 100): as conversas ligadas ao lead (`where(lead:)`, como o card da ficha). Devolve as `limite` mais recentes a partir de `desde`, da mais antiga para a mais nova, com `total` e `omitidas`. Cada mensagem: `direcao` (recebida/enviada), `horario`, `tipo`, `texto`, `origem` (contato, celular ou admin), `enviada_por`, `status` e `erro` das enviadas, `editada`, `do_historico` e `wamid`. Mídia vai entre colchetes: `[áudio]`, `[imagem] legenda`, `[documento: arquivo.pdf]`, `[template nome] texto`, `[mensagem apagada]`. Reações ficam de fora. Mensagem que a Meta não repassa à Cloud API (webhook `unsupported` com erro, como o 131060 "message unavailable" da coexistência, visto em resposta automática de IA de um contato) vira `[mensagem indisponível: a Meta não enviou o conteúdo à API (código 131060). Leia no app do WhatsApp Business]`, com o `erro` da Meta: o texto não chega ao Admin. A janela (`janela_aberta`, `janela_fecha_em`, `ultima_recebida_em`) vem da conversa que recebeu por último. Sem conversa: lista vazia e um `aviso`, que aponta a conversa com o número do lead ainda sem vínculo, se houver.
- **`com_resposta_whatsapp_desde`** no `buscar_leads`: só os leads com mensagem recebida (sem reação nem aviso do sistema) a partir do início do dia, numa conversa ligada a eles. Cada lead traz `respostas_whatsapp` (quantas no período) e `ultima_resposta_whatsapp` (`horario` e `texto`). Exige leitura na área WhatsApp.
- **IA ou automática**: a Meta não marca, nos webhooks `messages` e `smb_message_echoes`, se a mensagem saiu de IA ou de resposta automática do app (saudação, ausência, Business AI). Não há campo para gravar; o payload inteiro fica em `raw_payload`, para preencher depois se a Meta passar a mandar. A `origem` separa o que saiu do Admin (inclusive pelo `enviar_whatsapp`) do que saiu do celular.

### Escrita

| Tool | O que faz |
| --- | --- |
| `criar_leads` | Lote, com checagem de duplicados e modo `simular`. Substituiu a skill `adicionar-leads`, removida depois do conector em produção |
| `atualizar_lead` | Dados e próximo passo. `proximo_passo_em` em `AAAA-MM-DDTHH:MM` (Brasília); só a data vale às 09:00, como em `criar_leads`, `criar_oportunidade` e `atualizar_oportunidade` |
| `mover_lead` | Novo → Contato realizado → Qualificado |
| `converter_lead` | Via `LeadConversion` |
| `criar_oportunidade` / `atualizar_oportunidade` | Criação e alteração de valor, probabilidade, previsão, próximo passo |
| `mover_oportunidade` | Reunião, Proposta, Negociação ou Fechado. Fechado só registra data e 100%; não cria contrato |
| `marcar_perdido` | Lead ou oportunidade, com motivo da lista configurável |
| `registrar_interacao` | Ligação, WhatsApp, e-mail, reunião ou nota |
| `concluir_passo` | "Feito" da lista Próximos passos (`NextStepCompletion`, a mesma regra da tela): grava `o_que_foi_feito` como interação de hoje (`tipo_interacao`) e define o novo `proximo_passo` + `proximo_passo_em` **ou** `marcar_perdido` + `motivo`. Sem um dos dois, ou com os dois, é erro: nenhum item sai da lista sem próximo passo ou sem ser marcado como perdido |
| `criar_proposta` | Só como rascunho, com itens |
| `atualizar_proposta` | Proposta em Rascunho, Enviada ou Visualizada (`Proposal#editable?`, a mesma regra da tela). Só os campos enviados mudam. `itens`: com `id` (que `ver_proposta` passa a devolver) altera o item, com `remover: true` o exclui; sem `id`, adiciona (sem preço, vale o padrão do serviço). Não muda o status nem reenvia ao cliente |
| `gerar_pdf_proposta` | Links para abrir e baixar o PDF (gerado na hora; pedem login no sistema) |

### Envio ao contato

| Tool | O que faz |
| --- | --- |
| `enviar_whatsapp` | Texto ao WhatsApp de um lead em aberto, pelo número da DevBatista, com modo `simular`. Exige escrita na área WhatsApp |

Regras de `enviar_whatsapp`:

- **Aprovação**: annotations `destructiveHint: true`, `openWorldHint: true`, `idempotentHint: false`, título "Enviar WhatsApp (requer aprovação)"; a descrição manda simular, mostrar a prévia e só enviar o texto exato que o usuário aprovou. No claude.ai, deixar a tool em "sempre perguntar" nas permissões do conector: as annotations são só dicas para o cliente.
- **Número**: o campo WhatsApp do lead (`Whatsapp::Phone.wa_ids`, com e sem o nono dígito) acha a conversa da conta conectada; o envio vai para o número da conversa, na forma que a Meta usa. Número na conversa de outro cadastro é recusado.
- **Janela de 24h**: `WhatsappConversation#window_open?`, a mesma regra da tela (`last_inbound_at`, gravado pelo webhook a cada mensagem recebida, inclusive resposta automática do contato). Fechada: erro "fora da janela de 24h, precisa de template aprovado", com a data da última mensagem recebida.
- **Lead perdido ou convertido**: recusado.
- **Duplicidade**: o mesmo texto na conversa nos últimos 2 minutos é recusado, conferido com a conversa travada. O envio sem confirmação da Meta conta como enviado.
- **Envio**: `Whatsapp::Outbound#deliver_now` → `WhatsappSendJob.deliver_now`, na hora e sem novas tentativas, com o token e o `phone_number_id` do `WhatsappAccount`. A mensagem aparece na conversa do Admin como as outras.
- **Sucesso**: liga a conversa ao lead e grava a interação "WhatsApp" no lead com o texto e o wamid (além da automática do dia, que só leva as contagens). Devolve `{enviado, wamid, para, enviado_em}`.
- **Erro da Meta**: a mensagem fica "Falhou" na conversa, sem interação; volta o código, a mensagem em português e a original da Meta.
- **Segunda etapa**: `enviar_whatsapp_template` (primeiro contato fora da janela) e a lista dos templates aprovados.

### Escritório de agentes

Para as rotinas agendadas do Claude que trabalham como agentes da DevBatista (área `agentes`). Regras em [Escritório de agentes de IA](../escritorio-agentes/README.md).

| Tool | O que faz |
| --- | --- |
| `registrar_evento` | O agente (pela chave) registra status, título, resumo e, se for o caso, o pedido de aprovação |
| `ler_pendencias` | Ordens pendentes e decisões não lidas do agente; marca as decisões como lidas |
| `concluir_pendencia` | Conclui uma ordem do agente, com a resposta |

### Visitas do site

Só leitura, com números agregados das visitas ao devbatista.com (área `marketing`). Regras em [Visitas do site](../visitas-do-site/README.md).

| Tool | O que faz |
| --- | --- |
| `visitas_resumo` | Indicadores do período (visitantes, visitas, páginas vistas, rejeição, duração), comparação com o período anterior e série por dia, hora ou mês |
| `acessos_ia` | Robôs e agentes de IA que leram o site (treino, busca, a pedido de alguém), por empresa, agente, tipo, página ou dia, com a verificação de cada acesso |
| `visitas_por_dimensao` | Visitas agrupadas por canal (inclusive Assistentes de IA), origem, UTM, página, página de entrada ou de saída, dispositivo, navegador, sistema, dia da semana ou hora |

### Fora do MCP

Exclusões; enviar proposta ao cliente (`deliver`); WhatsApp com mídia ou template (por enquanto); aprovar ou recusar proposta (`ProposalApproval` gera contrato e recebíveis); qualquer área fora do Comercial, do Escritório e das visitas do site; administração.

## Arquitetura

```
config/routes.rb                    match "/mcp" → Mcp::Endpoint (app Rack)
config/initializers/mcp.rb          exceções das tools → Rails.error (log)
app/services/mcp/endpoint.rb        MCP::Server com as tools registradas + transporte Streamable HTTP stateless, JSON
app/services/mcp/token_verifier.rb  token → User (tokens do Doorkeeper; token fixo só em desenvolvimento)
app/services/mcp/metadata.rb        documentos de descoberta do OAuth
app/services/mcp/tools/base.rb      Current.user, Pundit, erros → resposta legível
app/services/mcp/tools/*.rb         uma classe por tool
config/initializers/doorkeeper.rb   servidor de autorização OAuth
app/controllers/oauth_metadata_controller.rb   /.well-known/oauth-protected-resource(/mcp) e /.well-known/oauth-authorization-server
app/views/doorkeeper/authorizations/           tela de consentimento, no layout de login
lib/tasks/mcp.rake                  bin/rails mcp:oauth_app (cadastra o app OAuth do Claude)
```

- Gem oficial `mcp` (SDK Ruby), transporte **stateless** com resposta JSON, sem SSE.
- Respostas em JSON enxuto: valores em reais, rótulos em português, ids em UUID.
- Listas com limite (padrão 25, até 50) e paginação.
- Erro de validação ou permissão volta como resultado de erro legível, para o Claude corrigir e tentar de novo.

## OAuth (Fase 4)

- Doorkeeper como servidor de autorização. `/oauth/authorize` usa o login do Devise e recusa quem não é administrador ativo.
- Um app OAuth pré-cadastrado (`bin/rails mcp:oauth_app`), com Client ID e Client Secret informados nas configurações avançadas do conector no claude.ai. Não há cadastro dinâmico de clientes.
- Só o fluxo authorization code, com PKCE S256 e escopo `mcp`. Token de acesso de 1 hora, refresh token, e o refresh anterior é revogado quando o token novo é usado.
- O banco guarda só o hash dos tokens, dos códigos e do secret do app.
- Descoberta: `/.well-known/oauth-protected-resource/mcp` (RFC 9728) e `/.well-known/oauth-authorization-server` (RFC 8414). Sem token, `/mcp` responde 401 com `WWW-Authenticate` apontando para a primeira.
- O endereço público vem de `APP_HOST` (`config.x.mcp.base_url`); é ele que identifica o recurso e o emissor.

## Conectar no claude.ai (Fase 5)

1. Deploy do branch. A migration roda sozinha (`db:prepare` no entrypoint). `APP_HOST` precisa ser o domínio público do app.
2. No Railway: `railway ssh` e `bin/rails mcp:oauth_app`. Guarde o Client Secret: ele só aparece nessa hora (para trocar: `ROTATE=1`).
3. No claude.ai: Configurações → Conectores → Adicionar conector personalizado. URL `https://<APP_HOST>/mcp`; em Configurações avançadas, o Client ID e o Client Secret.
4. Conectar: abre o login do Admin, depois a tela de consentimento; ao autorizar, volta ao claude.ai.
5. O conector vale no web, no Desktop e no celular.

## Fases

1. ✅ **Fundação**: gem `mcp`, endpoint `/mcp`, `Mcp::Tools::Base`, token de desenvolvimento, tool `opcoes_comerciais`; teste com o MCP Inspector e o Claude Code.
2. ✅ **Leitura**: tools de leitura e auxiliares, com specs.
3. ✅ **Escrita**: tools de escrita, com specs de permissão negada e erro de validação.
4. ✅ **OAuth**: Doorkeeper, metadata, consentimento, specs do fluxo.
5. **Produção**: deploy no Railway, conector no claude.ai, teste de ponta a ponta no web e no celular.

## Pontos resolvidos

- `mover_oportunidade` para "Fechado": sem efeitos colaterais além de `closed_on` e probabilidade 100% (o mesmo que arrastar no quadro). Contrato, serviços contratados e empresa Ativa só vêm de `ProposalApproval`, pela tela. A tool fica com "Fechado", e a descrição orienta o Claude a usar só quando o usuário disser que fechou.
- `gerar_pdf_proposta` devolve links em vez do arquivo: não há garantia de que o claude.ai mostre um PDF embutido no resultado da tool, e o link abre o PDF atual com o login do usuário.
- `atualizar_oportunidade` entrou além do previsto, no mesmo molde de `atualizar_lead`.

## Testar localmente (Fase 1)

```bash
MCP_DEV_TOKEN=um-token-qualquer bin/dev
claude mcp add --transport http devbatista-local http://localhost:3000/mcp --header "Authorization: Bearer um-token-qualquer"
```

O token de desenvolvimento só vale em `development` e `test`, e entra como o usuário de `MCP_DEV_USER` (e-mail) ou, sem ele, o primeiro administrador ativo.
