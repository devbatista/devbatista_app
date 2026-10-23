# MCP do Admin DevBatista — v1 (Comercial)

Outubro de 2026 · Servidor MCP (Model Context Protocol) dentro do próprio app, para o Admin DevBatista virar um **conector do Claude** (claude.ai, Desktop, celular e Claude Code).

## Decisões

| Tema | Decisão |
| --- | --- |
| Áreas na v1 | Só **Comercial**: leads, pipeline, oportunidades, propostas e interações |
| Escrita | Leitura + criação e alteração. **Sem exclusão**, sem enviar nada ao cliente, sem mexer em dinheiro |
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
| `buscar_leads` | Filtros: termo, status, origem, responsável, só abertos |
| `ver_lead` | Dados, interações, oportunidades e propostas |
| `pipeline` | Leads e oportunidades por etapa, com quantidade e valor estimado |
| `buscar_oportunidades` / `ver_oportunidade` | Lista e detalhe |
| `buscar_propostas` / `ver_proposta` | Itens, total, validade e status |

### Escrita

| Tool | O que faz |
| --- | --- |
| `criar_leads` | Lote, com checagem de duplicados e modo `simular`. Substitui a skill `adicionar-leads` |
| `atualizar_lead` | Dados e próximo passo |
| `mover_lead` | Novo → Contato realizado → Qualificado |
| `converter_lead` | Via `LeadConversion` |
| `criar_oportunidade` / `mover_oportunidade` | Criação e etapa (ver ponto em aberto sobre "Fechado") |
| `marcar_perdido` | Lead ou oportunidade, com motivo da lista configurável |
| `registrar_interacao` | Ligação, WhatsApp, e-mail, reunião ou nota |
| `criar_proposta` | Só como rascunho, com itens |
| `gerar_pdf_proposta` | Via `ProposalPdf`, devolve o arquivo |

### Fora do MCP

Exclusões; enviar proposta ao cliente (`deliver`); aprovar ou recusar proposta (`ProposalApproval` gera contrato e recebíveis); qualquer área fora do Comercial; administração.

## Arquitetura

```
config/routes.rb                    match "/mcp" → Mcp::Endpoint (app Rack)
config/initializers/mcp.rb          exceções das tools → Rails.error (log)
app/services/mcp/endpoint.rb        MCP::Server com as tools registradas + transporte Streamable HTTP stateless, JSON
app/services/mcp/token_verifier.rb  token → User (Fase 1: token de desenvolvimento; Fase 4: Doorkeeper)
app/services/mcp/tools/base.rb      Current.user, Pundit, erros → resposta legível
app/services/mcp/tools/*.rb         uma classe por tool
```

- Gem oficial `mcp` (SDK Ruby), transporte **stateless** com resposta JSON, sem SSE.
- Respostas em JSON enxuto: valores em reais, rótulos em português, ids em UUID.
- Listas com limite (padrão 50) e paginação.
- Erro de validação ou permissão volta como resultado de erro legível, para o Claude corrigir e tentar de novo.

## OAuth (Fase 4)

- Doorkeeper como servidor de autorização; tela de consentimento com o login do Devise, só para admin.
- Um app OAuth pré-cadastrado, com `client_id` e `client_secret` informados nas configurações avançadas do conector no claude.ai (dispensa o cadastro dinâmico de clientes).
- PKCE S256, redirect `https://claude.ai/api/mcp/auth_callback`, refresh token.
- Metadata exigida pelo MCP: `/.well-known/oauth-protected-resource` (RFC 9728) e `/.well-known/oauth-authorization-server` (RFC 8414). Sem token, `/mcp` responde 401 com `WWW-Authenticate` apontando para a metadata.

## Fases

1. **Fundação**: gem `mcp`, endpoint `/mcp`, `Mcp::Tools::Base`, token de desenvolvimento, tool `opcoes_comerciais`; teste com o MCP Inspector e o Claude Code.
2. **Leitura**: tools de leitura e auxiliares, com specs.
3. **Escrita**: tools de escrita, com specs de permissão negada e erro de validação.
4. **OAuth**: Doorkeeper, metadata, consentimento, specs do fluxo.
5. **Produção**: deploy no Railway, conector no claude.ai, teste de ponta a ponta no web e no celular.

## Em aberto

- `mover_oportunidade` para "Fechado": verificar efeitos colaterais; se houver, a transição sai da tool.

## Testar localmente (Fase 1)

```bash
MCP_DEV_TOKEN=um-token-qualquer bin/dev
claude mcp add --transport http devbatista-local http://localhost:3000/mcp --header "Authorization: Bearer um-token-qualquer"
```

O token de desenvolvimento só vale em `development` e `test`, e entra como o usuário de `MCP_DEV_USER` (e-mail) ou, sem ele, o primeiro administrador ativo.
