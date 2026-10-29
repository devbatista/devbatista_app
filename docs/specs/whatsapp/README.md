# WhatsApp Business no Admin DevBatista — v1

Outubro de 2026 · Integração com a **Cloud API da Meta** para conversar pelo WhatsApp de dentro do Admin, ligado aos leads e contatos. A DevBatista é Tech Provider na Meta (app "DevBatista Admin", portfólio DevBatista), e o primeiro número é o da própria DevBatista, em **coexistência** com o app WhatsApp Business do celular. O protótipo está em [`docs/design/whatsapp`](../../design/whatsapp/README.md).

## Decisões

| Tema | Decisão |
| --- | --- |
| Contas | Várias contas conectadas (uma por número). Na v1, o número da DevBatista; depois, números de clientes |
| Conexão | Embedded Signup da Meta (v5), em Tecnologia → Integrações → WhatsApp. O token fica criptografado (Active Record Encryption) e fora da auditoria |
| Identificação do contato | Pelo **BSUID** (business-scoped user ID), na coluna `bsuid`. Telefone (`wa_id`) e @usuário são opcionais |
| Primeiro contato | Só por template aprovado. Mensagem livre só com a janela de 24h aberta |
| Vínculo | Cada conversa liga a um lead **ou** a um contato, ou fica sem vínculo |
| Usuários | Na v1, só o administrador (área `whatsapp` na matriz de permissões). Autor e responsável por usuário ficam prontos para liberar ao Comercial depois |
| Desconexão | Em coexistência, feita no app do celular. O sistema reage ao `account_update` (`PARTNER_REMOVED`) |
| Fora da v1 | Sugestão de resposta por IA (virá do agente SDR via MCP, que segue sem enviar nada ao cliente até revisão), grupos e chamadas; aviso com o Admin fechado (push com service worker) |

## O que a Meta mudou (confirmado na documentação em outubro de 2026)

- **BSUID.** Desde abril de 2026, os webhooks trazem o ID do usuário (`contacts[].user_id`, `messages[].from_user_id`, `statuses[].recipient_user_id`), no formato `BR.13491208655302741918`. O telefone (`wa_id`, `from`) **pode não vir**: só vem se houve troca de mensagem pelo número nos últimos 30 dias ou se a pessoa está no contact book. O BSUID vale **por portfólio**, então a chave da conversa é conta + BSUID.
- **Envio.** `to` para telefone ou `recipient` para BSUID; com os dois, `to` vence. Templates de autenticação one-tap, zero-tap e copy code exigem telefone.
- **Troca de BSUID.** Chega em `messages` com `type: "system"`: `user_changed_number` (trocou de telefone; traz `user_id` novo e `previous_user_id`) ou `user_changed_user_id` (sem telefone). Não existe webhook `user_id_update`.
- **Coexistência.** Sincronizar contatos e histórico (`POST /<PHONE_NUMBER_ID>/smb_app_data`, `sync_type` `smb_app_state_sync` e `history`) só pode ser chamado **uma vez** por conexão e em até **24h**. O histórico vai até 180 dias, chega em pedaços fora de ordem (`chunk_order`, `progress`) e, se a pessoa recusar, vem o erro `2593109`. Mídia só dos últimos 14 dias. Mensagens enviadas pelo app chegam em `smb_message_echoes` e **não abrem nem estendem a janela de 24h**. Velocidade fixa de 20 mensagens/s.
- **Embedded Signup.** O `code` devolvido vale 30 segundos (a troca por token acontece na própria requisição). As versões 2 e 3 foram descontinuadas em 15/10/2026. O Admin usa a **v5** (lançada em 20/10/2026), em que a coexistência vem ligada por padrão: sem `featureType` e sem `sessionInfoVersion`, só `extras: { version: "v5" }` no `FB.login`.

- **Limite de envio.** O campo `messaging_limit_tier` do número foi descontinuado. O limite agora é do portfólio, compartilhado por todos os números, e se lê no número em `whatsapp_business_manager_messaging_limit` (ex.: `TIER_250`). A coluna `messaging_limit_tier` da conta guarda esse valor.
- **Erros da sincronização.** Chamar o `smb_app_data` de novo dá `2593107`; depois de 24h, `2593108`. Nos dois casos, só desconectando e conectando de novo.
- **Mídia.** O ID recebido por webhook vale 7 dias; a URL de download, 5 minutos, e exige o token. Limites: imagem 5 MB, áudio e vídeo 16 MB, documento 100 MB, figurinha 100 KB (500 KB animada).

## Configuração

Tudo pelo ambiente (`.env.example`); nenhum segredo no código.

| Variável | Para quê |
| --- | --- |
| `META_APP_ID`, `META_APP_SECRET` | App da Meta. O secret valida a assinatura dos webhooks e troca o `code` do Embedded Signup |
| `WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID` | Configuração do Embedded Signup (Facebook Login for Business) |
| `WHATSAPP_WEBHOOK_VERIFY_TOKEN` | Texto combinado com a Meta na verificação do webhook |
| `WHATSAPP_GRAPH_VERSION` | Versão da Graph API (padrão `v26.0`) |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `..._DETERMINISTIC_KEY`, `..._KEY_DERIVATION_SALT` | Criptografia do token. Gere com `bin/rails db:encryption:init`. Sem elas, valem as credentials; em desenvolvimento, chaves derivadas do secret local; em teste, valores fixos de teste |
| `REDIS_URL` | O Redis do Sidekiq também serve o ActionCable (tempo real das conversas), em desenvolvimento e em produção (`config/cable.yml`; sem a variável, `redis://localhost:6379/1`). No Railway, já está no serviço web. Em teste, o adapter `test` |

Os valores ficam em `Rails.configuration.x.whatsapp`.

**Chaves de criptografia em produção.**

- As três `ACTIVE_RECORD_ENCRYPTION_*` precisam estar no Railway **antes da Fase 4**: sem elas, a conexão do número falha ao salvar o token. Se faltar alguma (no ambiente e nas credentials), a inicialização em produção registra um erro no log (`config/initializers/active_record_encryption_check.rb`), sem derrubar o Admin.
- **Trocar ou perder as chaves torna ilegíveis os tokens já salvos**: guarde uma cópia segura no cofre de senhas. Sem ela, a saída é conectar o número de novo.

## Modelo de dados

| Tabela | Conteúdo |
| --- | --- |
| `whatsapp_accounts` | Portfólio, WABA, `phone_number_id` (único), número exibido (vazio até a ativação ler o número), nome verificado, token criptografado e validade (`token_expires_at`), status (Conectando, Aguardando registro, Conectado, Reconectar necessário, Desconectado), erro da ativação (`activation_error`), coexistência, qualidade e limite de envio, quem conectou, datas de conexão, inscrição do app, registro (`registered_at`) e desconexão, pedidos e datas das sincronizações, último webhook, andamento da sincronização de templates (`templates_sync_requested_at`, `templates_synced_at`, `templates_sync_error`) |
| `whatsapp_conversations` | Conta, `bsuid` e `parent_bsuid`, `wa_id` e @usuário opcionais, nome do perfil, nome salvo na agenda do celular (`saved_name`), lead **ou** contato, quando e quem vinculou (`linked_at`, `linked_by_id`; vazio é o vínculo automático), quando foi desvinculada à mão (`auto_link_blocked_at`), última mensagem recebida (janela de 24h), não lidas e prévia |
| `whatsapp_messages` | Direção, tipo, origem (Admin, Celular, Contato), corpo, `wa_message_id` único, status (Enviando, Enviada, Entregue, Lida, Falhou, Recebida), erro, template e parâmetros, mídia (Active Storage e o ID da mídia na Meta), mensagem citada (`reply_to_wa_message_id`), reação (`reaction_to_wa_message_id` e `reaction_emoji`), autor, se veio do histórico, datas de envio, entrega, leitura, edição e exclusão, payload bruto |
| CRM (Fase 7a) | Leads e contatos ganham `whatsapp_digits` e `phone_digits` (colunas geradas, só os dígitos, com índice). A interação ganha `whatsapp_conversation_id`: a automática, única por conversa, cadastro e dia |
| `whatsapp_templates` | Conta, ID na Meta, nome, idioma, categoria, status, componentes (formato da Graph API), nº de variáveis do cabeçalho e do corpo, motivo de rejeição, última sincronização. O excluído fica no banco com status `deleted`; nome e idioma são únicos por conta só entre os não excluídos |

Garantias no banco: o BSUID e o telefone são únicos por conta; a conversa precisa de BSUID ou telefone e não liga lead e contato ao mesmo tempo (check constraints); o `wa_message_id` é único, o que torna o processamento dos webhooks idempotente.

Respostas e reações: a resposta guarda o `context.id` da mensagem citada em `reply_to_wa_message_id`. A reação (tipo `reaction`) guarda o alvo e o emoji e aparece **sobre a mensagem reagida**, não como mensagem nova: `WhatsappMessage.timeline` exclui as reações e `#reactions` lista as de cada mensagem. Fica só a reação mais nova de cada lado (contato ou empresa) sobre cada mensagem. Emoji vazio é a pessoa removendo a reação; ele fica gravado para um reenvio atrasado da reação antiga não voltar, e a tela não mostra.

O BSUID fica em `bsuid`, e não em `user_id`, porque nesta base `user_id` é sempre o usuário dono do registro: a `ApplicationPolicy` usa essa coluna no nível de permissão "own".

## Cliente da Graph API (Fase 2)

`Whatsapp::Client.new(account)`, em `app/services/whatsapp/client.rb`, no padrão do `BcbPtax`: `Net::HTTP`, timeouts (5 s para conectar, 30 s para ler, 120 s para upload e download), sem gem nova.

| Método | Graph API |
| --- | --- |
| `send_text`, `send_media`, `send_template` | `POST /<PHONE_NUMBER_ID>/messages`. Destinatário pela conversa: `to` (telefone) ou `recipient` (BSUID). `reply_to:` vira `context.message_id`. Devolve `SentMessage` (wamid, telefone, BSUID) |
| `mark_as_read` | `POST /<PHONE_NUMBER_ID>/messages` com `status: "read"` |
| `upload_media`, `media`, `download_media`, `delete_media` | `POST /<PHONE_NUMBER_ID>/media` (multipart); `GET /<MEDIA_ID>` e a URL temporária com o token. O download vai em pedaços para um `Tempfile` e confere o `sha256`. Respeita o limite do tipo (pelo `mime_type`; `image/webp` é figurinha): recusa antes de baixar se o `file_size` informado passar dele e interrompe se o total baixado passar, mesmo sem `file_size` |
| `templates`, `create_template`, `update_template`, `delete_template` | `/<WABA_ID>/message_templates` (com paginação) e `POST /<TEMPLATE_ID>`. A categoria vai em maiúsculas; `update_template` só a manda quando muda (nunca para aprovado) |
| `upload_template_sample` | Exemplo da mídia do cabeçalho para a análise: `POST /<APP_ID>/uploads?file_name&file_length&file_type` (token da conta) abre a sessão `upload:…`; `POST /<sessão>` com `Authorization: OAuth <token>`, `file_offset: 0` e o arquivo devolve o handle (`h`). Respeita os limites por tipo. Não é o `/media` das mensagens |
| `subscribe_app`, `unsubscribe_app`, `subscribed_apps` | `/<WABA_ID>/subscribed_apps` |
| `phone_number_details` | `GET /<PHONE_NUMBER_ID>?fields=…` (nome, qualidade, limite de envio, coexistência) |
| `request_sync(:contacts / :history)` | `POST /<PHONE_NUMBER_ID>/smb_app_data`. Devolve o `request_id` |
| `register(pin:)` | `POST /<PHONE_NUMBER_ID>/register` com o PIN de 6 dígitos da verificação em duas etapas. Só para número sem coexistência (ver Fase 4 em "Pontos em aberto") |
| `Client.exchange_code(code)` | `GET /oauth/access_token?client_id&client_secret&code`, sem conta e sem cabeçalho de autorização |
| `Client.debug_token(token)` | `GET /debug_token` com o token do app (`app_id\|app_secret`): validade (`expires_at`, 0 quando não expira) e WABAs liberadas (`granular_scopes[].target_ids`) |
| `phone_numbers` | `GET /<WABA_ID>/phone_numbers` (id, número exibido, nome verificado) |

- `Whatsapp::TemplateComponents.build` monta os parâmetros do envio de template: corpo posicional ou nomeado, cabeçalho de texto ou de mídia, sufixo do botão de URL (codificado segmento a segmento, mantendo as barras: `p/P-2026-029` continua `p/P-2026-029`).
- `WhatsappTemplate.attributes_from_meta` e `WhatsappAccount.attributes_from_phone_details` convertem os valores em maiúsculas da Meta para os enums. Status e categoria que a Meta tem e a fase 1 não tinha entraram nos enums: `limit_exceeded`, `archived`, `pending_deletion` e `free_service`. Valor que a Meta passar a mandar e os enums não conhecem não para a sincronização: o status vira `pending`, a categoria fica a do template atual (`current:`) ou `utility`, e o log registra `[Whatsapp] valor desconhecido: campo=valor, template=nome`. A qualidade do número desconhecida vira `unknown`.
- Toda falha levanta `Whatsapp::Error`, com o erro da Meta separado (`code`, `details`, `fbtrace_id`, status HTTP):
  - `transient?` diz se vale tentar de novo: rede, erro 5xx, limite de envio, erro marcado como transitório. Nunca para pagamento (131042), qualidade do número (131048), limite de marketing por pessoa (131049, reenviar só depois de 24h), conta bloqueada (131031, 368) e número sem registro (133010), mesmo que a Meta marque `is_transient`;
  - `window_closed?` (131047), `token_invalid?` (190) e `rate_limited?`;
  - `user_message` traz o texto em português para a tela.
- O log registra só método, caminho, código e `fbtrace_id`. O token não vai para o log nem para o `inspect`.

## Webhook (Fase 3)

`/webhooks/whatsapp`, em `Webhooks::WhatsappController`, que herda de `ActionController::API`: fica fora do login, do Pundit, do bloqueio de navegadores e do CSRF.

- **Verificação (GET):** devolve o `hub.challenge` quando `hub.mode` é `subscribe` e o `hub.verify_token` confere com `WHATSAPP_WEBHOOK_VERIFY_TOKEN`; senão, 403.
- **Eventos (POST):**
  - Confere o `X-Hub-Signature-256`, que é o HMAC-SHA256 do corpo cru com o `META_APP_SECRET`. Sem assinatura válida, ou sem o secret configurado, responde 401.
  - Com a assinatura válida, responde 200 na hora e enfileira um `WhatsappWebhookJob` por mudança (`entry[].changes[]`).
  - A Meta reenvia por até 7 dias o que não receber 200.
- **Log:** o payload (mensagens, telefones, nomes) não vai para nenhum log.
  - Na requisição, o corpo (`entry`) é filtrado.
  - O `WhatsappWebhookJob` tem `log_arguments = false`, então o Active Job não registra os argumentos ao enfileirar nem ao executar.
  - Quando um job falha, o Sidekiq registra o job inteiro. O handler de erro (`config/initializers/sidekiq.rb`) troca os argumentos por `[FILTERED]` nos jobs com `log_arguments = false`.
  - O `WhatsappMediaJob` registra só a referência da mensagem (GlobalID).
  - Os logs do processador levam só IDs e códigos.
  - A mensagem de erro do PostgreSQL para índice único traz o valor duplicado (o telefone). Ela é tratada no `locate!` e no `record` e só chegaria ao log se esbarrasse três vezes seguidas.

**Configurar no app da Meta** (WhatsApp → Configuração):
- **URL de callback:** `https://admin.devbatista.com/webhooks/whatsapp`.
- **Token de verificação:** o mesmo valor de `WHATSAPP_WEBHOOK_VERIFY_TOKEN`.
- **Campos a inscrever:** `messages`, `smb_message_echoes`, `history`, `smb_app_state_sync`, `account_update`, `message_template_status_update`, `template_category_update`, `phone_number_quality_update` e `phone_number_name_update`.

O `Whatsapp::WebhookProcessor` trata cada campo. A conta é achada pelo `metadata.phone_number_id` ou, nos campos sem número, pela WABA (`waba_info.waba_id` ou `entry.id`). Webhook de número que não está no Admin fica só no log.

| Campo | O que acontece |
| --- | --- |
| `messages` | Mensagem recebida: acha ou cria a conversa (abaixo), grava a mensagem, abre a janela de 24h, soma às não lidas e atualiza a prévia. Mídia é baixada para o Active Storage pelo `WhatsappMediaJob`. Reação substitui a anterior da pessoa e não conta como não lida nem abre a janela. `request_welcome` é ignorado |
| `messages` (sistema) | `user_changed_user_id` e `user_changed_number`: a conversa antiga (`previous_user_id`, telefone antigo em `from`) fica com o BSUID ou o telefone novo, e o aviso entra na linha do tempo, sem contar como não lida |
| `messages` (status) | Enviada → entregue → lida, só avançando: webhooks fora de ordem não voltam o status, e a leitura e a gravação acontecem com a mensagem travada (`with_lock`), para dois status ao mesmo tempo não se sobrescreverem. `played` conta como lida. A falha guarda o código e a mensagem em português de `Whatsapp::Error::MESSAGES`. O `recipient_user_id` completa o BSUID da conversa iniciada pelo telefone |
| `smb_message_echoes` | Enviada pelo app do celular: mensagem de origem "Celular", zera as não lidas (quem respondeu no app já leu) e não mexe na janela. `edit` e `revoke` alteram a mensagem original (`edited_at`, `revoked_at`) |
| `history` | Mensagens antigas com `from_history`, sem abrir a janela nem contar como não lidas. Do celular, o status vem do `history_context`. Guarda o progresso (`history_sync_progress`, `history_synced_at` em 100) e a recusa (`2593109`) em `history_sync_error`. A mídia que veio como `media_placeholder` chega depois e completa a mensagem |
| `smb_app_state_sync` | Nome salvo na agenda (`saved_name`), que vira o nome da conversa. Cria a conversa ainda sem mensagem, para o nome não se perder; a caixa de entrada usa `WhatsappConversation.with_messages`. `remove` apaga o nome |
| `account_update` | `PARTNER_REMOVED`, `PARTNER_APP_UNINSTALLED`, `ACCOUNT_DELETED` e `ACCOUNT_OFFBOARDED` desconectam o número (data do evento e motivo, ex.: `PARTNER_REMOVED: ACCOUNT_DISCONNECTED`), mantendo as conversas. `ACCOUNT_RECONNECTED` reconecta depois do `ACCOUNT_OFFBOARDED`. Violação, restrição e banimento vão para o log |
| `message_template_status_update` | Status e categoria pelo ID na Meta ou por nome e idioma (o webhook manda `en-US`; o banco usa `en_US`), com o motivo da rejeição. `REINSTATED` e `UNARCHIVED` voltam a aprovado; `FLAGGED` e `LOCKED` só vão para o log |
| `template_category_update` | Troca a categoria quando a mudança foi concluída (`previous_category`); o aviso de troca futura vai para o log |
| `phone_number_quality_update`, `phone_number_name_update` | Relê nome, qualidade e limite na Graph API (`phone_number_details`); se a chamada falhar, fica o limite do webhook |

**Conversa pelo BSUID e pelo telefone** (`WhatsappConversation.locate!`). O BSUID é a identidade e o telefone completa:
- A conversa achada só pelo telefone e sem BSUID é da mesma pessoa e é juntada à do BSUID (`absorb!`). Por exemplo, a conversa criada pelo telefone ao iniciar com template e a resposta que chega com o BSUID. A junção leva as mensagens, o vínculo, as não lidas e as datas.
- Se a conversa do telefone tem **outro** BSUID, o número mudou de dono: o telefone sai da conversa antiga.
- Dois jobs criando a mesma conversa esbarram no índice único (`RecordNotUnique`), e o segundo tenta de novo.

**Idempotência:**
- Mensagem que já entrou (`wa_message_id`) é ignorada, inclusive quando dois jobs a gravam juntos.
- Status de mensagem ainda não gravada levanta `StatusTargetMissing` depois de processar o resto. O job tenta de novo 3 vezes, a cada 15 s, e depois desiste com uma linha no log.
- A mídia tenta de novo só nas falhas transitórias (`Whatsapp::Error#transient?`).

## Conexão (Fase 4)

Tecnologia → Integrações → **WhatsApp Business** (`/technology/integrations/whatsapp`, `Technology::WhatsappAccountsController`; atalho na tela de Integrações). Ver a tela exige leitura na área `whatsapp`; conectar, registrar e retomar exigem nível "full".

**No navegador** (controller Stimulus `whatsapp-signup`):
- O SDK da Meta (`connect.facebook.net/en_US/sdk.js`) é carregado só nesta tela, com `FB.init({ appId, autoLogAppEvents, xfbml, version: WHATSAPP_GRAPH_VERSION })`.
- "Conectar WhatsApp" mostra antes um aviso da coexistência: os aparelhos conectados são desconectados (o WhatsApp para Windows não é compatível), as listas de transmissão viram só leitura, as mensagens temporárias e de visualização única são desligadas e o app precisa ficar aberto no celular durante a sincronização.
- `FB.login` com `config_id`, `response_type: "code"`, `override_default_response_type: true` e `extras: { version: "v5" }`.
- O listener de `message` aceita só `https://` de `facebook.com` ou subdomínio e `type: "WA_EMBEDDED_SIGNUP"`:
  - **`FINISH`** (v5): `phone_number_id`, `messaging_account_ids[0]` (a WABA), `business_id` e `is_on_biz_app`. Também aceita o formato da v4 (`waba_id`, `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING`).
  - **`CANCEL`**: a tela mostra o passo (`current_step`) ou o erro reportado. Ao servidor vão só o passo, o código e o `session_id`, para o log.
- Com o `code` e o session info, envia os dois (POST JSON com o token CSRF). Se o session info não chegar em 5 s, envia só o `code`. O `code` não vai para o console.

**No servidor**, na própria requisição (`Whatsapp::Signup`), por causa dos 30 s do `code`:
1. `Client.exchange_code`.
2. `Client.debug_token`: confere que o token é válido e do app da DevBatista e lê o `expires_at`. As WABAs liberadas são os `target_ids` de `whatsapp_business_management` e `whatsapp_business_messaging`:
   - com session info, a WABA dele precisa estar entre elas; senão, a conexão é recusada ("A conta informada pela janela da Meta não corresponde à autorização. Conecte de novo."). Sem `target_ids` no `debug_token`, não há com o que conferir e o session info vale;
   - sem session info, a WABA vem delas e o número, de `GET /<WABA>/phone_numbers`. Com vários números, fica o que ainda não está conectado; se continuar ambíguo, a tela pede para conectar de novo.
3. Cria ou atualiza a conta pelo `phone_number_id`. Reconectar o mesmo número reaproveita o registro e as conversas, volta para Conectando e limpa a desconexão e o erro da ativação. As marcas da ativação (inscrição, registro, `request_id`s, datas e progresso das sincronizações, `history_sync_error`):
   - são **zeradas só se a conta estava desconectada** (no celular ou pela Meta): para a Meta é uma conexão nova, com novo prazo de 24h, e a ativação pede as sincronizações de novo;
   - **ficam** na renovação do token (conta Conectando, Aguardando registro, Conectada ou Reconectar necessário). Com os `request_id`s preenchidos, a ativação não pede a sincronização outra vez.
4. Enfileira o `WhatsappActivationJob` (só com a referência da conta) e responde. A tela recarrega e acompanha a ativação.

Sem `META_APP_ID`, `META_APP_SECRET`, `WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID` ou as chaves de criptografia (`Whatsapp.missing_signup_configuration`), a tela avisa o que falta, o botão fica desabilitado e o SDK não é carregado.

**Ativação** (`WhatsappActivationJob`, `log_arguments = false`). Etapas em ordem; cada uma grava sua marca e é pulada quando já foi feita, então o job retoma de onde parou:

| Etapa | Marca |
| --- | --- |
| 1. `subscribe_app` na WABA | `subscribed_at` |
| 2. `phone_number_details`: nome, qualidade, limite e coexistência (`is_on_biz_app`) | relida a cada execução, para valer o estado atual do número |
| 3. Sem coexistência e sem registro na Cloud API (`platform_type` diferente de `CLOUD_API`): para em **Aguardando registro**. A tela pede o PIN de 6 dígitos da verificação em duas etapas e chama `register(pin:)` na própria requisição. O PIN não é salvo nem vai para log ou job. Com coexistência, não há `register` | `registered_at` |
| 4. Só com coexistência: `request_sync(:contacts)` e depois `request_sync(:history)`, uma única vez cada (com a conta travada) e em até 24h da conexão | `contacts_sync_request_id`, `history_sync_request_id` |
| 5. Conectado (ou Aguardando registro, na etapa 3) | `status`, gravado com a conta travada e relida, só se ela ainda estiver em Conectando |

- Uma desconexão (`account_update`) que chegue pelo webhook durante a ativação prevalece: o job não pede as sincronizações de conta que já não está em Conectando e não sobrescreve o status.
- Falha transitória (`Whatsapp::Error#transient?`) tenta de novo (5 tentativas).
- Falha definitiva, inclusive token inválido (`190`), e tentativas esgotadas ficam em `activation_error`, em português. A tela mostra o erro e o botão **Tentar de novo**, que retoma da etapa que falhou.
- Erros da sincronização, sem retry. Em ambos o número fica conectado:
  - **`2593107`** é sincronização já pedida antes. A coluna do `request_id` recebe o marcador `already-requested`, para não pedir de novo. Se alguma sincronização já chegou (`contacts_synced_at`, `history_synced_at` ou progresso do histórico), não há aviso;
  - **`2593108`** (fora das 24h), ou `2593107` sem nenhuma sincronização registrada: fica o aviso em `activation_error`, e a tela explica que o caminho é desconectar no celular e conectar de novo.

**Tela** (segue `docs/design/whatsapp/conexao.html`):
- Cada número mostra o status, a coexistência e a linha do tempo: autorizado, app inscrito, contatos e histórico (com o progresso em %) ou registro, recebendo mensagens.
- Detalhes: nome exibido, qualidade, limite, velocidade de 20 mensagens/s na coexistência, portfólio, WABA, ID do número, quem conectou e quando, validade do acesso.
- A lista se atualiza sozinha (turbo-frame e controller `refresh`, a cada 5 s) enquanto há ativação em andamento, ou histórico em andamento no primeiro dia da conexão. Não recarrega com um campo em foco.
- Cartões "App da Meta" e "Webhook" com os valores do ambiente e da conta. Segredos aparecem só como "Configurado". "Último evento" vem do `last_webhook_at`.
- **Desconectar** (coexistência): só o diálogo com o caminho no celular (Configurações → Conta → Plataforma comercial → Desconectar conta). Não existe chamada na API.

**Validade do token.** Vem do `expires_at` do `debug_token` (0, sem validade, fica vazio).
- A tela avisa a partir de 7 dias do fim.
- A rotina diária (`WhatsappTokenExpiryJob`, chamada pelo `DailyAlertsJob` às 7h) marca as contas com o token vencido como **Reconectar necessário**.
- O botão **Reconectar** abre o mesmo cadastro. A renovação mantém as sincronizações (passo 3 acima).

**Segurança.**
- O `code`, o token e o PIN não vão para log, `inspect`, payload de job nem tela.
- `code` e `pin` estão em `filter_parameter_logging`, pelo nome exato.
- O Admin não envia `Cross-Origin-Opener-Policy` nem `Content-Security-Policy`, que bloqueariam a janela e o `postMessage` da Meta; um request spec garante isso. Se um dia tiverem CSP, liberar `connect.facebook.net` e `facebook.com`, e o COOP não pode ser `same-origin`.

## Templates (Fase 5)

WhatsApp → **Templates** (`/whatsapp/templates`, `WhatsappTemplatesController`), seguindo `docs/design/whatsapp/templates.html`. O item saiu do "em breve" do menu; Conversas continua até a Fase 6.

**Lista.**
- KPIs: Aprovados, Em análise, Rejeitados (com o nome e o motivo do mais recente) e Pausados.
- Seletor de conta quando há mais de uma; a padrão é a primeira não desconectada.
- Filtro por status, busca no nome e no texto do corpo, paginação.
- Cada linha mostra:
  - o motivo da rejeição traduzido ou a explicação do status (pausa, desativação), ou o início do corpo;
  - a ação por status: Editar, ou Corrigir se rejeitado; em análise, "aguardando a Meta"; nos demais, Ver.
- Os excluídos não aparecem. O rodapé lembra as regras da Meta.
- Motivos de rejeição: `WhatsappTemplate::REJECTION_REASONS` (`INCORRECT_CATEGORY`, `TAG_CONTENT_MISMATCH`, `INVALID_FORMAT`, `ABUSIVE_CONTENT`, `SCAM`, `PROMOTIONAL`). O webhook grava "CÓDIGO — detalhe" e a sincronização só o código. Código desconhecido aparece cru e vai para o log (`[Whatsapp] motivo de rejeição desconhecido`) quando é gravado.

**Sincronização** (`WhatsappTemplateSyncJob`, uma por conta):
- Pelo botão "Sincronizar com a Meta" (a lista se atualiza sozinha enquanto roda) e pela rotina diária (`DailyAlertsJob`, 7h, para as contas com acesso válido).
- Lê `Client#templates` (todas as páginas). Grava pelo `meta_template_id` ou, se o template do Admin ainda não tem ID, por nome e idioma, com `attributes_from_meta(data, current:)` e `last_synced_at`. Sem motivo na Meta (`NONE`), o motivo antigo sai.
- Os criados direto no Gerenciador do WhatsApp entram na lista.
- O template que sumiu da Meta fica como excluído (`deleted`), sem apagar: as mensagens antigas apontam para ele por nome e idioma. Isso acontece antes de gravar os da Meta, para um template novo com o mesmo nome não esbarrar no antigo.
- Conta desconectada ou com o token vencido não sincroniza nem cria templates, e a tela explica o motivo.
- Falha transitória tenta de novo (5 vezes). A definitiva, e a transitória esgotada, ficam em `templates_sync_error`, em português, na tela.

**Editor** (páginas Novo e Editar, com a prévia ao lado; controller Stimulus `template-editor`). Os campos viram components no `Whatsapp::TemplateBuilder`, um objeto de formulário testável, separado da tela:

| Campo | Regras |
| --- | --- |
| Conta, idioma | Só contas com acesso válido. Idiomas `pt_BR`, `en_US` e `es`. Bloqueados na edição |
| Nome | `a–z`, `0–9` e `_`, conferido no navegador (`pattern`) e no builder. Bloqueado na edição. Nome e idioma já existentes na conta são recusados antes de chamar a Meta |
| Categoria | Marketing ou Utilidade. Autenticação (e Atendimento) vindos da Meta ficam só para leitura |
| Cabeçalho | Nenhum; texto (até 60 caracteres, no máximo `{{1}}`, com exemplo em `example.header_text`); ou mídia (imagem JPEG/PNG, documento PDF, vídeo MP4) com o exemplo enviado por `upload_template_sample` e o handle em `example.header_handle` |
| Corpo | Obrigatório, até 1024 caracteres. Variáveis `{{1}}`, `{{2}}`… em sequência, sem começar nem terminar com variável e sem duas seguidas; um exemplo obrigatório por variável (`example.body_text`). "+ Adicionar variável" insere a próxima |
| Rodapé | Opcional, até 60 caracteres, sem variável |
| Botões | Até 10: respostas rápidas, até 2 links (URL fixa ou com `{{1}}` no fim, com exemplo da URL completa) e 1 telefone. Texto até 25 caracteres. As respostas rápidas vão primeiro, porque a Meta pede os botões agrupados por tipo |

- A prévia "como o contato vê" mostra os exemplos no lugar das variáveis e é atualizada ao vivo. Na tela Ver, ela é renderizada no servidor, com o mesmo partial.
- O handle do exemplo de mídia volta no formulário num campo oculto, para não escolher o arquivo de novo se outro campo der erro.
- O `variables_count` (cabeçalho + corpo) é calculado pelo model a partir dos components.

**Criação:** `create_template`, com a categoria em maiúsculas. Grava `meta_template_id`, status e a categoria devolvida, que pode já vir diferente; a tela avisa ("A Meta classificou como Marketing").

**Edição:**
- Só aprovado, rejeitado ou pausado, via `update_template`. Volta para Em análise e limpa o motivo.
- Do aprovado, a categoria não muda e a tela avisa antes que ele volta para análise.
- "Corrigir" (rejeitado) mostra o motivo no topo e permite trocar a categoria.
- Os limites de edição (1 por dia, 10 por mês) são da Meta: o Admin não conta e mostra o erro dela.

**Exclusão:**
- Confirmação explicando os 30 dias. `delete_template` com o `hsm_id`, então só aquele idioma sai da Meta. No banco, fica como excluído.
- Bloqueada enquanto houver mensagem com o template ainda Enviando. Envio agendado ainda não existe; quando existir, entra em `WhatsappTemplate#pending_sends?`.

**Auditoria:** criação, edição (mudança de status) e exclusão vão para o `AuditLog`, sem os components.

## Conversas e tempo real (Fase 6)

WhatsApp → **Conversas** (`/whatsapp/conversations`, `WhatsappConversationsController`), seguindo `docs/design/whatsapp/conversas.html`. O item saiu do "em breve" do menu.

**Tempo real.**
- O `ApplicationCable::Connection` identifica o usuário pela sessão do Devise (`env["warden"].user`) e recusa a conexão sem login ou de usuário inativo.
- Todos os streams do WhatsApp usam o `WhatsappStreamsChannel` (`turbo_stream_from …, channel: WhatsappStreamsChannel`). Além do nome assinado, ele exige que a pessoa possa ver a área WhatsApp.
- Os broadcasts saem dos `after_commit` dos models e são renderizados num job (`broadcast_*_later`). Por isso funcionam a partir do webhook no Sidekiq e da requisição, e mudam só a mensagem ou o item da lista.

| Stream | O que muda |
| --- | --- |
| `[conta, :whatsapp_inbox]` (lista) | Mensagem nova tira o item de onde estiver, inclusive das páginas carregadas depois, e o põe no topo. Não lidas, prévia, nome, vínculo e janela redesenham o item |
| `[conversa, :whatsapp]` (conversa aberta) | Mensagem nova; status (Enviando → enviada → entregue → lida → falhou), edição, exclusão e mídia baixada substituem o balão; reação redesenha a mensagem reagida; janela que abre ou fecha redesenha o cabeçalho e o campo de envio |
| `:whatsapp_menu` (contador) | Total de conversas com mensagem e não lidas (`WhatsappConversation.menu_unread_count`, uma consulta) |

- As partes renderizadas no broadcast não dependem de quem vê, porque não há sessão no job. "Responder", "Tentar de novo" e o campo de envio levam `data-send-only` e somem por CSS para quem só lê a área. O servidor confere a permissão de novo.
- Os jobs de broadcast levam só o nome do stream, o alvo, o partial e a referência (GlobalID), nunca o conteúdo.

**Tela.**
- **Lista:**
  - seletor de conta quando há mais de uma;
  - busca por nome do perfil, nome da agenda, telefone (dígitos) e @usuário;
  - filtros Todas, Não lidas, Leads, Clientes, Sem vínculo e Janela aberta, com a contagem numa consulta só;
  - sempre `with_messages`, ordenada pela última mensagem;
  - paginação por cursor (última mensagem + id) num turbo-frame lazy, sem pular nem repetir.
- **Nome:** agenda > perfil > telefone (+55 11 99102-3344) > @usuário > "Contato do WhatsApp" (`WhatsappConversation#display_name`).
- **Conversa** (turbo-frame; abrir pela lista recarrega só ela):
  - cabeçalho com o telefone, ou "telefone não compartilhado" quando só há BSUID, e a janela ("Janela aberta · fecha em 5h (até 18/09 10:42)" ou "Janela fechada desde …");
  - linha do tempo com separador por dia, avisos do sistema, autor, marcas Celular, Template e Histórico, links seguros (`rel="noopener noreferrer"`);
  - mídia: imagem com ampliação, áudio e vídeo com player, documento com nome e tamanho, figurinha, "baixando…" até o `WhatsappMediaJob` terminar;
  - resposta citando a original (o clique leva até ela) e reações agrupadas;
  - selo "editada", "Mensagem apagada", status com ícones e a falha em português com "Tentar de novo".
  - Abre na última mensagem. As anteriores carregam ao rolar até o topo, por cursor (`sent_at` + id), mantendo a posição.
- **Painel:**
  - dados do WhatsApp: perfil, agenda, telefone ou "Não compartilhado", @usuário, BSUID, primeira mensagem e conta;
  - o vínculo, só o nome com link para a ficha, ou "Conversa sem lead ou contato". Criar e vincular ficam para a Fase 7.
- **Telas estreitas:** as colunas viram navegação (lista → conversa → painel), pelo controller `whatsapp-screen`.

**Campo de envio** (controller `whatsapp-composer`):
- **Janela aberta:**
  - texto até 4096 caracteres (Enter envia, Shift+Enter quebra a linha);
  - anexo (imagem, documento, áudio ou vídeo; legenda nos tipos que aceitam), conferido pelo tipo (`WhatsappMessage::UPLOAD_TYPES`) e pelo tamanho (`MEDIA_LIMITS`) antes de enviar;
  - "Responder" cita a mensagem (`context`).
- **Janela fechada:** texto e anexo bloqueados, com a explicação, e o botão "Responder com template".
- **Modo template:**
  - os aprovados da conta (com categoria e idioma) e o link para "Gerenciar templates";
  - um campo por variável (o `{{1}}` e as variáveis nomeadas conhecidas já vêm preenchidos desde a Fase 7b), a mídia do cabeçalho quando o template pede, o fim do link dos botões de URL com variável, e a prévia;
  - os campos e o envio são descritos por `Whatsapp::TemplateFields`, para o servidor e para o navegador.
- A resposta do envio já traz o balão "Enviando". O broadcast do mesmo balão tem o mesmo id e só o substitui, porque o Turbo não duplica.
- Quando a janela fecha com a conversa aberta, ela é recarregada.

**Envio** (`Whatsapp::Outbound` na requisição, `WhatsappSendJob` no Sidekiq):
1. A requisição confere a permissão, a conta (só conectada) e a janela no servidor: texto e mídia só com ela aberta, template sempre.
2. Grava a mensagem de saída (Enviando, origem Admin, autor, template e parâmetros, mídia no Active Storage) e atualiza a prévia.
3. Enfileira o job e responde.

O `WhatsappSendJob` (`log_arguments = false`):
- **Envio:**
  - texto (`send_text`, com prévia do link quando há URL);
  - mídia (`upload_media`, com o ID guardado para não subir de novo, e `send_media`);
  - template (`send_template` com `TemplateComponents.build`: corpo posicional ou nomeado, cabeçalho de texto ou de mídia, sufixo dos botões);
  - sempre com a citação.
- **Depois da resposta da Meta:** grava o `wa_message_id` sem callbacks e completa o telefone ou o BSUID da conversa com o que a Meta devolveu.
- **Falha transitória:** tenta de novo com espera curta (3, 10, 30, 60 s), mantendo "Enviando"; esgotadas as tentativas, falha. No POST da mensagem, só quando o pedido não saiu ou o erro transitório é da própria Meta.
- **Sem confirmação da Meta** no POST da mensagem (timeout de leitura, conexão interrompida): falha sem nova tentativa, com "A Meta não confirmou o envio. Ele pode ter chegado ao contato: confira antes de tentar de novo." (ver "Pontos em aberto").
- **Falha definitiva:** o status vai para falhou, com o código e a mensagem de `Whatsapp::Error::MESSAGES`.
  - `131047` fecha a janela na tela.
  - `131062` sugere o template ou o telefone.
  - `190` leva a conta a "Reconectar necessário".
  - Conta não conectada é recusada antes de chamar a Meta.
- **Sem duplicar:** mensagem com `wa_message_id` nunca é enviada de novo. "Tentar de novo" cria outra mensagem; a que falhou fica.

**Leitura.**
- Abrir a conversa, ou receber mensagem com ela aberta e a aba visível, zera as não lidas e enfileira o `WhatsappReadJob`.
- O job chama `mark_as_read` com a última mensagem recebida, sem travar a conversa durante a chamada. Depois da resposta, grava o `read_at` só nas recebidas que ainda estão sem ele, então cada mensagem é marcada uma vez só.
- Na falha, o log leva só o código e o `fbtrace_id` da Meta.
- Os ticks azuis aparecem para o contato.
- Responder pelo celular continua zerando as não lidas (Fase 3).

**Mídia:** a action `media` exige permissão e redireciona para uma URL temporária do serviço (`blob.url(expires_in: 5.minutes)`, S3 em produção). Não usa o `rails_blob_path`, que é permanente e abre sem login. A imagem aparece reduzida por CSS, sem variant, porque o Railway pode não ter libvips.

**Índices** (migration da Fase 6): lista por conta (`last_message_at DESC, id DESC`, só com mensagem), não lidas e janela por conta, linha do tempo por conversa (`sent_at, id`).

**Testes:** channel specs, request specs, `WhatsappSendJob`, `WhatsappReadJob` e broadcasts a partir do webhook. O projeto não tem Capybara nem Cuprite, então não há system spec; o fluxo no navegador (abrir conversa, enviar e ver o balão) fica para o teste em produção.

## Vínculo com o CRM (Fase 7a)

O painel da conversa liga a conversa a um lead ou a um contato, mostra os dados do CRM e registra uma interação "WhatsApp" por dia de conversa. "Iniciar conversa", os cards no lead, na empresa e no contato e o preenchimento das variáveis do template estão na Fase 7b, logo abaixo.

**Telefone** (`Whatsapp::Phone`):
- O mesmo celular do Brasil pode chegar com e sem o nono dígito depois do DDD: a Meta manda um ou outro conforme a conta, e o cadastro pode ter qualquer um dos dois.
- `stored_forms(wa_id)` dá as formas em que o número da conversa pode estar no CRM, só os dígitos: com e sem o 55, com e sem o 0 do DDD e, no celular, com e sem o 9. `wa_ids(telefone)` faz o caminho de volta, do telefone como foi digitado para os `wa_id` possíveis (10 ou 11 dígitos sem o código do país são do Brasil). Fixo e número de fora do Brasil ficam como estão.
- Leads e contatos têm `whatsapp_digits` e `phone_digits`, colunas geradas pelo banco (só os dígitos, com índice). A busca olha o WhatsApp e o telefone do cadastro.

**Vínculo automático:**
- Conversa com telefone e sem vínculo se liga sozinha quando há **um único** candidato: um lead em aberto (Novo Lead, Contato Realizado, Qualificado) ou um contato. Acontece quando a conversa ganha o telefone (`before_save`) e quando um lead ou contato ganha o WhatsApp ou o telefone (`WhatsappAutoLinkJob`, pelo concern `WhatsappLinkable`).
- Com mais de um candidato, ou só leads convertidos ou perdidos, não vincula: o painel mostra os cadastros em "Mesmo telefone", com "Vincular" em cada um.
- `linked_at` e `linked_by` guardam quando e quem vinculou; sem `linked_by`, foi pelo telefone.
- **Desvinculada à mão:** "Desvincular conversa" grava `auto_link_blocked_at`, e o vínculo automático deixa a conversa de fora (`auto_link!`, e o scope `WhatsappConversation.auto_linkable`, usado pelo `WhatsappAutoLinkJob` e pela rake). Mensagem nova, cadastro salvo de novo com o mesmo número ou a rake não a ligam de novo.
  - A marca cai quando a conversa é vinculada à mão ou quando ganha outro telefone (`wa_id`). Com telefone novo, o vínculo automático tenta na hora.
  - O painel continua mostrando os candidatos em "Mesmo telefone", com "Vincular" manual, e avisa que o vínculo automático está desligado.
- **Depois do deploy:** `bin/rails whatsapp:link_conversations` liga as conversas que já existiam. Pode rodar mais de uma vez; as desvinculadas à mão ficam de fora.

**Painel** (com a sessão de quem vê, porque os dados seguem a permissão de cada área):
- **Lead:** nome e empresa com link para a ficha, status, contato, e-mail, origem, serviço e responsável; a etapa (Novo Lead → Oportunidade, ou a da oportunidade aberta que o lead virou); propostas em aberto; próximo passo; as três últimas interações e "+ Registrar".
- **Contato:** a empresa com link para a Visão 360º, o contato e o cargo, o e-mail, o responsável e a etapa da oportunidade aberta da empresa; propostas em aberto da empresa; próximo passo e interações da oportunidade. Sem oportunidade aberta, avisa.
- **Sem vínculo:** "Criar lead", "Vincular a lead/contato existente" e os candidatos pelo telefone. Sem telefone, explica que não há busca automática.
- "Desvincular conversa", com confirmação. As interações já registradas continuam no cadastro.
- Mover a etapa e editar o próximo passo ficam na ficha e no pipeline.
- Quando o vínculo muda, o broadcast troca o painel por um turbo-frame com `src` (`panel_frame`), que busca o painel de novo (action `panel`) com a permissão de quem está vendo. O broadcast não leva dados do CRM.

**Gavetas** (a gaveta lateral do Admin):
- **Criar lead** (`WhatsappConversationLeadsController`): nome da agenda ou do perfil, WhatsApp "(11) 99102-3344", origem WhatsApp, responsável, status em aberto e as três primeiras mensagens de texto recebidas nas observações ("Chegou pelo WhatsApp em …"). Cria o lead e vincula na mesma transação.
- **Vincular** (`WhatsappConversationLinksController`): sem busca, os cadastros com o telefone da conversa; com busca, nome, empresa, e-mail e telefone (a partir de 4 dígitos). Só entram os leads e contatos que a pessoa pode ler. "Salvar o telefone no WhatsApp do cadastro" grava o número só quando o campo está vazio.
- **Registrar interação** (`Commercial::InteractionsController#new`): o mesmo registro manual do lead e da oportunidade, que volta para a conversa.

**Interação "WhatsApp" automática** (`WhatsappInteractionJob`):
- Uma por conversa, cadastro e dia (`interactions.whatsapp_conversation_id`, índice único), em nome do responsável pelo lead ou pela oportunidade.
- Vai para o lead em aberto; o lead convertido, para a oportunidade aberta que ele virou; o lead perdido, para o próprio lead; o contato, para a oportunidade aberta da empresa. Contato sem oportunidade aberta fica sem interação.
- O texto leva só as contagens do dia ("Conversa do dia · 4 recebidas, 2 enviadas"), nunca o conteúdo. É refeito a cada mensagem, depois do commit. Não contam histórico, reação, aviso do sistema e envio que falhou.
- Vincular registra a de hoje, se já houve mensagem. Na ficha e no painel, a interação aparece marcada como "automática".
- A conversa juntada por troca de BSUID leva o vínculo e as interações da outra.

**Testes:** `Whatsapp::Phone`, vínculo automático (webhook, cadastro novo, candidatos, junção, desvinculada à mão que não religa), broadcast do painel, `WhatsappInteractionJob` e request specs do painel, das gavetas e das permissões.

## Iniciar conversa e cards no CRM (Fase 7b)

**Iniciar conversa** (`WhatsappConversationStartsController`, na gaveta lateral, seguindo `docs/design/assets/wa-iniciar.js`). O primeiro contato é sempre por template aprovado.
- **"Nova conversa"** (tela de conversas): busca os leads e contatos com WhatsApp cadastrado, por nome, empresa, e-mail ou telefone (`Lead.whatsapp_search` e `Contact.whatsapp_search`, os mesmos do "Vincular"). Os leads em aberto vêm primeiro.
- **Pelo cadastro** (cards no lead, na empresa e no contato): "Para Henrique Duarte · Grupo Norte · (11) 99102-3344", a conta (com mais de uma conectada, trocar recarrega os templates), o template aprovado com as variáveis e a prévia.
- **Sem WhatsApp válido no cadastro:** o formulário pede o número e oferece "Salvar no cadastro" (quando a pessoa pode alterar o cadastro).
- **Qual conversa:**
  - a do cadastro nesta conta;
  - senão, a do mesmo número, com e sem o nono dígito (`Whatsapp::Phone.wa_ids`);
  - senão, uma nova (`WhatsappConversation.locate!`).
  - O número numa conversa ligada a **outro** cadastro é recusado: "O número … já está na conversa com …. Abra a conversa para enviar."
- **Envio:** pelo `Whatsapp::Outbound`, como o template do campo de envio. Com erro (variável em branco, mídia do cabeçalho), o formulário volta com o que foi digitado, e a conversa só é apagada se nasceu vazia para este envio:
  - o `locate!` a criou agora (`previously_new_record?`), e não devolveu uma que o webhook criou no mesmo instante;
  - relida do banco, não tem mensagem nem vínculo feito por alguém (o vínculo automático pelo telefone, feito quando ela nasceu, não conta).
  - A conferência de "ligada a outro cadastro" vale também para a conversa que o `locate!` devolve. Com sucesso, a conversa fica ligada ao cadastro em nome de quem iniciou, e abre.
- **Telefone devolvido pela Meta:** o `WhatsappSendJob` grava na conversa o `wa_id` que a Meta devolve quando é o mesmo número em outra forma (com ou sem o nono dígito), para os webhooks seguintes acharem a conversa pelo telefone. Isso não conta como telefone novo: a marca de desvinculada à mão continua (`Whatsapp::Phone.same_number?`).

**Variáveis já preenchidas** (`Whatsapp::TemplateFields.person` e `#defaults`), no "Iniciar conversa" e no campo de envio da conversa:
- o `{{1}}` posicional recebe o primeiro nome;
- as nomeadas conhecidas (`PREFILL`): `nome`, `primeiro_nome`, `first_name` e `name` (primeiro nome), `nome_completo` e `full_name`, `empresa`, `company` e `company_name`;
- o nome vem do lead ou do contato vinculado; na conversa sem vínculo, do nome da agenda ou do perfil;
- as outras variáveis ficam em branco, e todas podem ser editadas antes do envio.
- Os campos e a prévia do template saíram do `whatsapp-composer` para o controller `whatsapp-template-fields` (partial `whatsapp_conversations/_template_fields`), usado nos dois lugares.

**Cards** (para quem lê as conversas; "Iniciar conversa" só para quem envia e vincula):
- **Lead** (ficha): a conversa mais recente com a janela e as três últimas mensagens (quem, quando, status), o telefone, a conta e "Abrir conversa". Sem conversa, "Iniciar conversa no WhatsApp"; sem WhatsApp cadastrado, o aviso, "Iniciar" (que pede o número) e "Editar lead".
- **Empresa** (Visão 360º, aba Resumo): cada contato com a conversa mais recente (prévia, não lidas, janela e "Abrir conversa"), ou o WhatsApp cadastrado e "Iniciar conversa".
- **Contatos** (lista): a ação "WhatsApp" abre a conversa do contato ou o "Iniciar conversa".
- Os cards usam `with_messages`, numa consulta por página (`whatsapp_latest_by_contact`).

**Testes:** request specs de "Nova conversa", do "Iniciar conversa" (número novo, nono dígito, número de outro cadastro, sem número, erro no template, contato), dos valores sugeridos no campo de envio, dos cards e das permissões; `TemplateFields.person` e `#defaults`; `WhatsappSendJob` com o número na forma da Meta.

## Avisos (Fase 8)

**Central de notificações** (`Notification::KINDS`):

| Tipo | Quem recebe | Quando | E-mail |
| --- | --- | --- | --- |
| `whatsapp_message` · Mensagens do WhatsApp | Administradores e quem vê a área WhatsApp (`area_readers`) | Mensagem recebida numa conversa | Desligado por padrão (`email_default: false`) |
| `whatsapp_token_expiring` · Acesso do WhatsApp vencendo | Administradores | 7 dias antes e no dia do vencimento do token | Ligado por padrão, como os outros tipos |

- **Um aviso por conversa, nunca um por mensagem** (`Whatsapp::Notifier`, chamado pelo processamento do webhook depois do commit):
  - mensagem recebida (fora do histórico, sem reação nem aviso do sistema) cria o aviso da conversa para cada usuário que recebe o tipo e ainda não tem um aviso não lido dela;
  - com um aviso não lido, ele é atualizado: "Henrique Duarte · 3 mensagens novas" (as não lidas da conversa), a prévia da última (`notifications.body`) e a data, que o leva ao topo da lista;
  - o aviso aponta a conversa (`notifiable` e `path`);
  - o índice único parcial `index_notifications_whatsapp_unread` garante um não lido por conversa e usuário, e o Notifier trabalha com a conversa travada;
  - mensagem cuja conversa alguém já abriu (não lidas zeradas) antes do aviso sair não gera aviso.
- **Lido:** abrir a conversa (`show` e `read`) e a resposta pelo celular (`smb_message_echoes`, que zera as não lidas) marcam como lidos os avisos daquela conversa, para todos os usuários. As não lidas que vão a zero disparam a marcação; abrir a conversa também marca o aviso que chegou depois de zeradas.
- **E-mail:** segue `User#email_for?`, só na criação do aviso. A preferência das mensagens começa desligada; a tela de preferências mostra o tipo para quem recebe.
- **Token vencendo** (`WhatsappTokenExpiryJob`, na rotina diária): atenção entre 7 e 1 dia antes (se a rotina falhar no 7º dia, avisa no seguinte) e crítico no dia, com `dedup_key` por conta, data de vencimento e etapa. Rodar duas vezes não repete; token renovado com outra data avisa de novo. O link leva a Tecnologia → Integrações → WhatsApp.

**Sino do topo em tempo real:**
- Stream por usuário, `[usuário, :notifications]`, pelo `NotificationsChannel`, que além do nome assinado confere que o stream é o do usuário conectado.
- Criar, atualizar ou ler um aviso (callback `after_commit` e `Notification.refresh_bell` nas marcações em lote) redesenha o botão (`notifications_bell_button`, com o ponto de não lidas) e a lista (`notifications_bell_list`). A lista renderizada no broadcast marca como lida por `data-turbo-method="patch"`, com o token CSRF da página.
- O stream fica num elemento permanente do layout (`#notifications_stream`, `data-turbo-permanent`), que não se reconecta a cada visita.

**Aviso do navegador com som** (só front, Stimulus):
- **Faixa** na tela de conversas (`whatsapp-notify-banner`), como no protótipo:
  - "Ativar avisos" pede a permissão (`Notification.requestPermission()` só no clique) e mostra um aviso de confirmação;
  - "Agora não" esconde a faixa para sempre;
  - a escolha fica no `localStorage` (`wa-avisos`, com try/catch: sem storage, vale só na visita);
  - com a permissão negada, sobra só a linha "Avisos do navegador bloqueados para este site…".
- **Disparo** (`whatsapp-alerts`, no layout, em todas as telas do Admin para quem vê a área):
  - o `Whatsapp::Notifier` acrescenta em `#whatsapp_alerts`, pelo stream do usuário, um alvo com o nome, a prévia (as mesmas da central), o id da conversa e da mensagem e o endereço. O controller lê e remove.
  - Não avisa se a conversa está aberta e a aba visível.
  - Várias abas: cada uma se candidata no `localStorage` (`wa-aviso-ultimo`, mensagem e aba), e só a que continua gravada depois de um instante avisa e toca.
  - `new Notification(nome, { body: prévia, tag: "whatsapp-<conversa>" })`: o aviso novo da conversa substitui o anterior; o clique foca a janela e abre a conversa.
- **Som:** `app/assets/sounds/whatsapp-aviso.wav` (dois toques curtos, gerado no projeto, sem dependência externa), tocado com `HTMLAudioElement` só depois da primeira interação com a página. "Som dos avisos do WhatsApp" no menu do usuário liga e desliga (`localStorage` `wa-som`); sem escolha, fica ligado para quem ativou os avisos.
- **Fora da v1:** aviso com o Admin fechado (push com service worker).

**Conferência manual do aviso do navegador e do som** (não há teste automatizado de navegador no projeto):
1. Em Conversas, com a permissão do site em "Perguntar", a faixa aparece. "Agora não" a esconde e ela não volta ao recarregar; apague `wa-avisos` no `localStorage` para vê-la de novo.
2. "Ativar avisos": o navegador pede a permissão. Ao permitir, chega o aviso "Avisos do WhatsApp ativados" e a faixa some. Ao bloquear, sobra a linha do cadeado.
3. Clique em qualquer lugar do Admin (desbloqueia o som). Com a conversa aberta e a aba visível, peça para alguém mandar mensagem: nada de aviso nem som, só o balão.
4. Abra outra conversa, ou outra tela (Dashboard, por exemplo), ou troque de aba: a mensagem gera o aviso com o nome e a prévia, e o som. Uma segunda mensagem da mesma conversa substitui o aviso anterior.
5. Clique no aviso: a janela ganha foco e a conversa abre. O sino do topo mostra o aviso da conversa ("N mensagens novas") sem recarregar, e ele fica lido ao abrir a conversa.
6. Com duas abas do Admin abertas, uma mensagem gera um aviso e um som só.
7. No menu do usuário, "Som dos avisos do WhatsApp: desligado": a próxima mensagem avisa sem som.
8. Responder pelo celular marca o aviso da conversa como lido no sino.

**Testes:** `Whatsapp::Notifier` (criação, atualização sem duplicar, novo aviso depois de lido, histórico, reação, sistema e eco sem aviso, eco marcando como lido, e-mail, broadcast ao navegador sem conteúdo nos argumentos do job), abrir a conversa marcando os avisos de todos, `WhatsappTokenExpiryJob` (7 dias e no dia, sem repetir), sino em tempo real (criado, atualizado, lido e em lote), `NotificationsChannel` e as preferências.

## Permissões e auditoria

- Área `whatsapp` em `Role::AREAS`. O Administrador tem nível "full"; os outros perfis começam sem acesso e podem ser liberados na tela de permissões.
- Policies `WhatsappConversationPolicy`, `WhatsappMessagePolicy` e `WhatsappTemplatePolicy` seguem a matriz. `WhatsappAccountPolicy` exige nível "full" para conectar ou alterar um número.
- Templates: quem só lê a área vê a lista, a prévia e os detalhes; criar, editar e sincronizar (`sync?`) exigem escrita; excluir exige "full".
- Avisos (Fase 8): o aviso de mensagem vai para quem vê a área WhatsApp; o sino e os avisos do navegador vêm pelo stream do próprio usuário (`NotificationsChannel`).
- Conversas: quem só lê a área vê as conversas e a mídia, e abrir marca como lida; enviar e "Tentar de novo" (`retry?`) exigem escrita. O canal do tempo real também exige a área.
- Iniciar conversa (Fase 7b): exige enviar (`WhatsappMessage#create?`) e vincular (`link?`); o destinatário precisa ser legível (Comercial ou Clientes). Os cards no CRM aparecem para quem lê as conversas.
- Vínculo (Fase 7a): vincular, criar lead e desvincular (`link?`) exigem escrita no WhatsApp; criar lead também exige criar no Comercial. O painel mostra os dados do lead só com leitura no Comercial e os do contato só com leitura em Clientes. "+ Registrar" segue a permissão de alterar o lead ou a oportunidade.
- `AuditLog` na conta (conexão, status) e nos templates, sem o token, sem o erro da ativação e sem os campos que a Meta atualiza sozinha. As conexões aparecem também nas atividades.

## Fases

0. ✅ **Protótipo**: telas em `docs/design/whatsapp`.
1. ✅ **Fundação**: configuração, tabelas, models, criptografia do token, área de permissão e policies, grupo no menu ainda como "em breve".
2. ✅ **Cliente da Graph API** em `app/services/whatsapp/` (Net::HTTP, sem gem nova): texto, mídia, template, marcar como lida, baixar mídia, templates, inscrição do app, troca do `code`, sincronizações.
3. ✅ **Webhook e processamento**: `/webhooks/whatsapp` fora do `ApplicationController`, assinatura `X-Hub-Signature-256`, job no Sidekiq, todos os campos inscritos, idempotente pelo `wa_message_id`, download da mídia.
4. ✅ **Conexão**: Embedded Signup v5 em Tecnologia → Integrações → WhatsApp, ativação em job (inscrição, registro ou sincronizações), validade do token.
5. ✅ **Templates**: lista, editor com prévia, criação, edição e exclusão na Meta, exemplo de mídia pelo upload retomável, sincronização pelo botão e diária.
6. ✅ **Conversas e tempo real**: tela de três colunas, Turbo Streams com ActionCable autenticado pelo Devise e Redis em desenvolvimento, campo de envio em Stimulus (texto, anexo, resposta, template), envio e leitura em jobs, contador no menu.
7. **Ligação com o CRM**, em dois PRs:
   - 7a. ✅ **Vínculo**: vínculo automático pelo telefone (com e sem o nono dígito), painel com os dados do CRM, criar lead, vincular e desvincular, interação "WhatsApp" automática (uma por dia de conversa).
   - 7b. ✅ **Iniciar conversa**: diálogo com template, "Nova conversa", cards no lead, na empresa e no contato, preenchimento das variáveis do template com os dados do cadastro.
8. ✅ **Avisos**: aviso por conversa e do token vencendo na central (`Notification::KINDS`), sino em tempo real, aviso do navegador com som.

## Pontos em aberto

- **Primeiro uso real (Fases 4 a 6)**, porque a documentação lida não mostra estes pontos:
  - O formato de envio do cabeçalho de mídia em template (`{ type: "document", document: { id } }`). Só a criação está documentada.
  - Se o token do Embedded Signup expira. O Admin lê o `expires_at` do `debug_token` (Fase 4) e trata o erro `190` pedindo para conectar de novo; conferir o valor que vem na primeira conexão.
  - A categoria em maiúsculas no `create_template` e no `update_template`. A referência usa maiúsculas e o exemplo, minúsculas; o Admin manda **maiúsculas** (`UTILITY`, `MARKETING`). Conferir no primeiro template criado em produção e registrar aqui o resultado.
  - O upload retomável do exemplo de mídia (`upload_template_sample`), pouco documentado. A confirmar com um template real:
    - o `id` da sessão vem com `?sig=…` e é usado inteiro no caminho do segundo POST;
    - o cabeçalho `Authorization: OAuth`;
    - o `Content-Type` `application/octet-stream`;
    - se o handle continua aceito ao editar um template sem trocar a mídia (o Admin reenvia o handle guardado nos components).
  - O código `131062` (BSUID não aceito para aquela mensagem): aparece na página do BSUID, não na tabela de erros.
  - O sufixo do botão de URL com barra (`p/P-2026-029`, link da proposta em `/p/*token`): conferir com um template de verdade que a Meta monta o link com as barras e decodifica os caracteres especiais.
  - Webhooks que a documentação lida não mostra por inteiro:
    - `to_user_id` nos ecos e `user_id` na agenda: o código já usa se vierem;
    - o `history` com BSUID no lugar do telefone em `threads[].id`;
    - edição e exclusão vindas do contato (só os ecos estão documentados).
  - Duas escolhas conservadoras sobre a janela de 24h, a confirmar:
    - **Reação recebida não abre a janela.** Se a Meta abrir, o Admin só pede template quando não precisaria.
    - **Mensagem do histórico não abre a janela.** Ela foi recebida no celular antes da conexão.
- **Templates por número.** Os templates são da WABA, mas ficam gravados por conta (número). Com um número por WABA, não muda nada. Com vários números na mesma WABA, o `meta_template_id` (único) só pode ficar numa conta: a sincronização da segunda conta deixa esses templates de fora, com aviso no log (`não sincronizado`). Nesse caso, ligar os templates à WABA.
- **Conversas vazias da agenda.** A sincronização da agenda (`smb_app_state_sync`) cria uma conversa vazia para cada contato do celular. A caixa de entrada mostra só as conversas com mensagem (`WhatsappConversation.with_messages`). As telas e contagens das próximas fases precisam usar esse scope:
  - lista de conversas e filtros;
  - contador de não lidas no menu;
  - cards no lead, na empresa e no contato;
  - indicadores.
- **Fase 4, a conferir no teste de ponta a ponta em produção** (o Embedded Signup só abre nos domínios cadastrados na Meta, então nada disso roda fora de `admin.devbatista.com`):
  - O payload da v5 (`FINISH`, `messaging_account_ids`, `is_on_biz_app`) e os nomes de `current_step` no `CANCEL`. A tela mostra o passo como a Meta manda.
  - Que os `target_ids` do `debug_token` são WABAs. O fallback sem session info e a conferência da WABA do session info dependem disso: se vierem outros IDs, toda conexão é recusada com "A conta informada pela janela da Meta não corresponde à autorização". O log de conexão registra os IDs para o diagnóstico.
  - O `platform_type` de um número sem coexistência recém-conectado (esperado: diferente de `CLOUD_API`, para pedir o PIN).
  - Entre a conexão e a leitura do número (etapa 2 da ativação), a conta ainda não tem `display_phone_number`. Nesses segundos, `account_update` e os webhooks de número que trazem o telefone ficam só no log.
- **Desconectar sem coexistência** (números de clientes): não há tela. Quando houver, usar `POST /<PHONE_NUMBER_ID>/deregister` e `unsubscribe_app`.
- **Fase 8 (resolvido):** o vencimento do token também avisa pela central (7 dias antes e no dia).
- **Fase 5 (resolvido):** a sincronização usa `WhatsappTemplate.attributes_from_meta`, como o webhook de status. O template criado direto no Gerenciador do WhatsApp entra na lista pela sincronização (botão ou rotina diária). Até lá, o status dele que chega pelo webhook fica só no log.
- **Fase 6 (resolvido):**
  - o `wa_message_id` é gravado logo depois da resposta do envio, e o status que chegar antes é reprocessado pela Fase 3;
  - a caixa de entrada e o contador usam `with_messages`;
  - a mensagem apagada aparece como "Mensagem apagada";
  - a reação com emoji vazio não aparece.
- **Fase 6, a conferir no uso real:**
  - **Envio sem confirmação da Meta não é tentado de novo**, para não duplicar no celular do contato (a Cloud API não tem chave de idempotência).
    - Casos: timeout de leitura, conexão interrompida, resposta inválida (`Whatsapp::Error#delivery_uncertain?`).
    - No POST da mensagem, a mensagem vai para falha com "A Meta não confirmou o envio. Ele pode ter chegado ao contato: confira antes de tentar de novo.", sem código da Meta. "Tentar de novo" fica com a pessoa, depois de conferir no celular.
    - Só tentam de novo o pedido que não saiu (timeout de conexão, conexão recusada, DNS, handshake SSL) e os erros transitórios da própria Meta. O upload da mídia, que não envia nada ao contato, tenta de novo em qualquer falha de rede.
    - Também já está coberto: o ID é gravado sem callbacks logo depois da resposta, e mensagem com ID nunca é reenviada.
  - Lista filtrada ou com busca: o broadcast põe no topo a conversa que recebeu mensagem mesmo que ela não combine com o filtro. Ao refazer a busca ou trocar o filtro, a lista volta a ficar certa.
  - A contagem de cada filtro é calculada ao abrir a tela e não muda com o tempo real.
  - O formato do cabeçalho de mídia no envio de template (primeiro item da lista "Primeiro uso real").
- **Fase 7a (resolvido):** o vínculo pelo telefone considera o nono dígito (`Whatsapp::Phone`); o painel tem os dados do CRM, "Criar lead" e "Vincular".
- **Fase 7a, a conferir no uso real:**
  - O vínculo automático com contato que tem o mesmo telefone de outro contato (sócios com o celular da empresa, por exemplo): fica sem vínculo e aparece em "Mesmo telefone".
  - O painel não acompanha em tempo real as mudanças feitas no cadastro (etapa, propostas, próximo passo): ele é atualizado ao abrir a conversa ou quando o vínculo muda.
- **Fase 7b (resolvido):** as variáveis do template já vêm preenchidas no campo de envio e no "Iniciar conversa"; a conversa iniciada pelo número do cadastro fica com o `wa_id` que a Meta devolve.
- **Fase 7b, a conferir no uso real:**
  - Que a Meta devolve em `contacts[].wa_id` a forma do número que ela usa (com ou sem o nono dígito) quando o envio vai pelo número digitado.
  - A lista de contatos e de leads da "Nova conversa" mostra até 10 de cada; acima disso, é pela busca.
  - Os cards no CRM não atualizam em tempo real: mostram a conversa ao abrir a página.
- **Fase 8 (resolvido):** aviso do navegador e som para mensagem nova, em todas as telas do Admin.
- **Fase 8, a conferir no uso real:**
  - O roteiro de conferência manual do aviso do navegador e do som (seção "Avisos").
  - Com a conversa aberta e a aba visível, o aviso da central é criado e marcado como lido logo em seguida (o servidor não sabe o que está na tela): o ponto do sino pode piscar.
  - Navegadores que bloqueiam som mesmo depois da interação (Safari com restrições de mídia): o aviso aparece sem som.
