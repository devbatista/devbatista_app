# Escritório de agentes de IA — v1

Novembro de 2026 · Página do Admin em que os agentes do Claude que trabalham para a DevBatista aparecem como personagens, cada um na sua sala. Nela o administrador acompanha o que cada um está fazendo, aprova ou rejeita o que pede aprovação e deixa ordens para a próxima execução.

## Decisões

| Tema | Decisão |
| --- | --- |
| Quem são os agentes | Rotinas agendadas do Claude (plano Pro) que acessam o Admin pelo servidor MCP em `/mcp` ([MCP do Admin](../mcp-comercial/README.md)) |
| Sentido das chamadas | **O Rails nunca chama a API do Claude.** Quem chama é sempre o Claude, pelo MCP. A tela só lê eventos e grava ordens e decisões, que o agente lê na próxima execução |
| Identidade do agente | Todos usam o mesmo conector (o token do administrador). O agente se identifica pela **chave** (`ops`, `sol`…) em cada tool. Chave desconhecida ou agente inativo é recusado |
| Agentes iniciais | Ops (SRE · Infra), Sol (SDR · Comercial), Mia (Marketing), Leo (Tráfego pago), Fin (Financeiro), criados pela seed em todos os ambientes |
| Status atual | O do último evento do agente. Sem evento, Ocioso. Um pedido de aprovação já decidido deixa de ser "aguardando": o agente aparece Ocioso até a próxima execução |
| Usuários | Na v1, só o administrador (área `agentes` na matriz de permissões) |
| Tempo real | Turbo Streams com ActionCable e Redis, no stream `escritorio`, no mesmo padrão do WhatsApp |
| Fora da v1 | Tela de Rotinas (agenda, prompt, última execução), cadastro e edição dos agentes pela tela, cancelar ordem, aviso na central de notificações |

## Princípio

O escritório é uma caixa de correio entre o administrador e os agentes:

```
Claude (rotina agendada) ──MCP──▶ registrar_evento ──▶ AgentEvent ──broadcast──▶ /escritorio
                                                                                    │
Claude (próxima execução) ◀──MCP── ler_pendencias ◀── AgentOrder / decisão ◀──── Rafael
```

- O agente registra o que fez (`registrar_evento`) e, quando precisa de aprovação, para e espera.
- O administrador aprova, rejeita (com observação opcional) ou deixa uma ordem na tela.
- Na execução seguinte, o agente lê as ordens e as decisões (`ler_pendencias`), age e responde (`concluir_pendencia`).

As tools rodam como o usuário do token (`Mcp::Tools::Base`): mesma matriz de permissões, mesma auditoria (`ip_address` `mcp:<ip>`).

## Modelo de dados

| Tabela | Conteúdo |
| --- | --- |
| `agents` | `key` (única, `a–z`), `name`, `title` (cargo), `room` (sala), `position` (ordem das salas na planta), `outfit_color`, `hair_color` e `skin_color` (`#RRGGBB`, para o sprite), `active` |
| `agent_events` | Agente, `status`, `title`, `summary`, `needs_approval`, `decision`, `decided_at`, `decided_by_id`, `decision_note`, `decision_read_at`, `payload` (jsonb opcional) |
| `agent_orders` | Agente, `body` (texto da ordem), `status`, `response`, quem deu a ordem (`user_id`), `delivered_at` (primeira leitura pelo agente), `completed_at` |

**Enums** (`labeled_enum`, chaves em inglês no banco, como no resto do projeto; rótulos na tela e na descrição das tools):

| Campo | Valores |
| --- | --- |
| `agent_events.status` | `working` Trabalhando · `idle` Ocioso · `awaiting_approval` Aguardando aprovação · `done` Concluído · `error` Erro |
| `agent_events.decision` | `pending` Pendente · `approved` Aprovado · `rejected` Rejeitado (vazio quando não precisa de aprovação) |
| `agent_orders.status` | `pending` Pendente · `completed` Concluída |

**Regras:**
- `needs_approval` ⇔ status `awaiting_approval`; com aprovação, `decision` nasce `pending`. Check constraint no banco.
- Só se decide evento `pending`, uma vez: grava `decision`, `decided_at` e `decided_by`. Decidir de novo é recusado.
- `decision_read_at` marca a decisão entregue ao agente por `ler_pendencias`.
- `payload` até 20 KB. Aparece na tela como JSON formatado, nunca como HTML.
- Título até 120 caracteres; resumo, ordem e resposta até 5.000.
- `Agent#status`: status do último evento (por `created_at`), com a exceção do pedido já decidido. `Agent#pending_approvals`: todos os eventos com `decision: pending`, não só o último.
- Índices: eventos por agente e data (`agent_id, created_at DESC`); pendentes de decisão (parcial, `decision = 'pending'`); decisões não lidas (parcial); ordens pendentes por agente.
- Auditoria: `Agent`, `AgentEvent` e `AgentOrder` com `include Auditable`, área `agentes`, `activity: false` (os eventos já são o histórico; não poluem o feed do dashboard).

## Tools do MCP

No padrão das existentes (`Mcp::Tools::Base`, respostas em JSON com chaves em português, erro legível para o Claude corrigir). Todas pedem `agente` (a chave) e exigem a área `agentes`.

| Tool | O que faz |
| --- | --- |
| `registrar_evento` | `agente`, `status`, `titulo`, `resumo`, `precisa_aprovacao` (padrão `false`), `dados` (objeto opcional, vai para `payload`). `precisa_aprovacao: true` grava o status Aguardando aprovação; status Aguardando aprovação implica `precisa_aprovacao`. Devolve o evento com id, status e link para o escritório |
| `ler_pendencias` | Ordens pendentes do agente (id, texto, quem deu, quando) e decisões ainda não lidas (evento, título, decisão, observação, quando). Marca as decisões como lidas e grava `delivered_at` na primeira leitura de cada ordem. As ordens continuam aparecendo até serem concluídas |
| `concluir_pendencia` | `agente`, `ordem_id`, `resposta`. Marca a ordem como concluída, com a resposta. Ordem de outro agente ou já concluída é recusada |

- `ler_pendencias` é de escrita (`writes`), porque marca as decisões como lidas.
- O texto de `INSTRUCTIONS` do endpoint passa a citar o escritório e o roteiro de cada execução: `ler_pendencias` no começo, `registrar_evento` ao trabalhar e ao terminar, `concluir_pendencia` para cada ordem atendida.

## Tela (Fase 1)

**Menu:** grupo novo **Agentes IA** (`NavigationHelper::NAV`, ícone próprio), com Escritório, Rotinas ("em breve") e Eventos.

**Escritório** (`/escritorio`, `EscritorioController#show`):
- **Planta** à esquerda. Na Fase 1, um cartão por sala (`--radius`), na ordem de `position`: nome, cargo, sala, chip de status e o título do último evento. Clicar abre o agente no painel.
- **Painel** à direita (Turbo Frame `agent_panel`, `/escritorio/agentes/:key`):
  - nome, cargo, sala e chip de status;
  - última tarefa (título e resumo do último evento) e há quanto tempo;
  - pedidos de aprovação pendentes, cada um com Aprovar, Rejeitar e observação opcional;
  - "Deixar uma ordem" (textarea + Enviar) e as ordens pendentes e concluídas do dia, com a resposta;
  - linha do tempo dos eventos de hoje (fuso do app), do mais novo para o mais antigo.
- Sem agente na URL, o painel abre o primeiro com aprovação pendente, ou o primeiro da planta.
- **Chips de status:** Trabalhando em ciano, Concluído em `--good`, Aguardando aprovação em `--warn`, Erro em `--crit`, Ocioso neutro.
- Telas estreitas: a planta em cima, o painel embaixo.

**Eventos** (`/escritorio/eventos`): listagem com filtros (agente, status, aprovação, período), ordenação por data e paginação. Cada linha abre o agente no escritório.

**Tempo real:**
- `turbo_stream_from :escritorio, channel: EscritorioStreamsChannel`. O canal exige leitura na área `agentes`, como o `WhatsappStreamsChannel`.
- `AgentEvent` e `AgentOrder`, na criação e na alteração (`after_commit on: %i[create update]`), chamam `Agent#broadcast_office`, que faz `broadcast_replace_later_to :escritorio`:
  - redesenha o cartão do agente na planta (`dom_id(agent, :desk)`);
  - troca as duas partes do painel daquele agente, `dom_id(agent, :panel)` (status, última tarefa e aprovações, em `/escritorio/agentes/:key/ao-vivo`) e `dom_id(agent, :log)` (ordens e linha do tempo, em `/registro`), por turbo-frames com `src`, que buscam de novo com a sessão de quem vê (os botões dependem da permissão);
  - o campo "Deixar uma ordem" fica entre as duas partes, fora do que o broadcast troca, para não perder o texto digitado.
- Um callback só para criação e alteração: `after_create_commit` e `after_update_commit` com o mesmo método ficariam só com o último (comportamento do Rails).
- `ler_pendencias` grava as leituras com `update_all` e chama o broadcast uma vez.
- Os jobs de broadcast levam só o stream, o alvo, o partial e o GlobalID.
- Cada cartão leva `data-agent-key` e `data-agent-status`, que a Fase 2 usa para mover os personagens. O controller Stimulus `escritorio` marca a sala do agente aberto no painel, inclusive depois do broadcast.
- Aprovar, rejeitar e deixar ordem respondem em Turbo Stream (redesenham as partes do painel e limpam o campo); sem Turbo, voltam ao escritório com o aviso.

**Permissões:**
- Área `agentes` em `Role::AREAS`. Administrador "full"; os outros perfis começam sem acesso.
- `AgentPolicy` e `AgentEventPolicy` (ler: `show?`; decidir: `decide?`, escrita) e `AgentOrderPolicy` (criar: escrita).
- O canal do tempo real e as tools do MCP seguem a mesma área.

## Planta em pixel art (Fase 2)

- Controller Stimulus `escritorio_controller.js` desenha num `<canvas>`, em JavaScript puro, pelo importmap. Sem React, sem Node, sem build.
- Grade de tiles de 24 px, cerca de 40 × 25:
  - em cima, 5 salas, uma por agente, com mesa, monitor, cadeira, estante e plantas;
  - no meio, um corredor;
  - embaixo, Diretoria (com o personagem "Rafael" na mesa), Lazer · Copa (cafeteira, geladeira, sofá, fliperama) e Reunião (mesa redonda).
- Pisos: madeira, carpete azul, carpete verde, azulejo xadrez na copa.
- Personagens em sprites próprios (PNG em `app/assets/images/escritorio`, ou desenhados em código com as cores do agente), com a etiqueta "Nome · Status" acima da cabeça.

| Status | Comportamento |
| --- | --- |
| Trabalhando | Na própria mesa, digitando, monitor aceso |
| Ocioso | Anda até a Copa e fica no café |
| Aguardando aprovação | Anda até a Diretoria e para na frente da mesa do Rafael, etiqueta piscando |
| Concluído | Volta para a mesa, com ✓ |
| Erro | Na mesa, etiqueta vermelha |

- Caminho por BFS na grade, desviando de paredes e móveis. Referência de ideia (não de código): Pixel Agents (github.com/pablodelucca/pixel-agents).
- Atualização ao vivo pelo stream `escritorio` (os cartões da Fase 1 ficam como fonte dos dados, escondidos, e o controller observa `data-agent-status`). Clicar num personagem abre o painel dele.
- Zoom (+ e −) no canto da planta.
- `prefers-reduced-motion`: sem caminhada nem piscar; o personagem aparece direto no destino.
- Sem assets de terceiros sem licença clara.

## Fases

1. ✅ **Base**: tabelas, models, área de permissão e policies, tools `registrar_evento`, `ler_pendencias` e `concluir_pendencia`, menu Agentes IA, Escritório com planta em cartões e painel, Eventos, tempo real, seeds (5 agentes e eventos de exemplo fora de produção), testes de models, tools, request e policies.
2. **Planta em pixel art**: canvas, tiles, sprites, BFS, comportamento por status, zoom, `prefers-reduced-motion`.

## Testes (Fase 1)

`spec/models/agentes_spec.rb` (status atual, aprovação e decisão, limites, auditoria, broadcasts), `spec/services/mcp/tools_agentes_spec.rb` (as três tools, agente desconhecido ou inativo, permissão, ordem de outro agente), `spec/requests/escritorio_spec.rb` (planta, painel, decisão, ordem, eventos, menu e 403), `spec/policies/agentes_policies_spec.rb` e `spec/channels/escritorio_streams_channel_spec.rb`. Sem system spec (o projeto não tem Capybara): o clique na sala e o tempo real no navegador ficam para a conferência manual.

## Pontos em aberto

- **Agente travado em Trabalhando.** Se a rotina cair depois de registrar Trabalhando, o agente fica assim até a próxima execução. Avaliar mostrar "sem notícias há X h" a partir de um limite.
- **Aprovação pendente atrás de evento novo.** O status é o do último evento: se o agente pedir aprovação e depois registrar Trabalhando, ele deixa de aparecer na Diretoria, mas o pedido continua no painel. A alternativa é Aguardando aprovação prevalecer enquanto houver pedido pendente.
- **Decisão lida e perdida.** `ler_pendencias` marca a decisão como lida na hora; se a rotina falhar logo depois, a próxima execução não a vê mais. O evento continua na tela com a decisão.
- **Aviso de aprovação** na central de notificações e no sino (`Notification::KINDS`), para não depender de abrir o escritório.
- **Retenção dos eventos.** Sem limite na v1; com poucas execuções por dia, o volume é pequeno.
