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
| Fora da v1 | Sugestão de resposta por IA (virá do agente SDR via MCP, que segue sem enviar nada ao cliente até revisão), grupos e chamadas |

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

Os valores ficam em `Rails.configuration.x.whatsapp`.

**Chaves de criptografia em produção.**

- As três `ACTIVE_RECORD_ENCRYPTION_*` precisam estar no Railway **antes da Fase 4**: sem elas, a conexão do número falha ao salvar o token. Se faltar alguma (no ambiente e nas credentials), a inicialização em produção registra um erro no log (`config/initializers/active_record_encryption_check.rb`), sem derrubar o Admin.
- **Trocar ou perder as chaves torna ilegíveis os tokens já salvos**: guarde uma cópia segura no cofre de senhas. Sem ela, a saída é conectar o número de novo.

## Modelo de dados

| Tabela | Conteúdo |
| --- | --- |
| `whatsapp_accounts` | Portfólio, WABA, `phone_number_id` (único), número exibido (vazio até a ativação ler o número), nome verificado, token criptografado e validade (`token_expires_at`), status (Conectando, Aguardando registro, Conectado, Reconectar necessário, Desconectado), erro da ativação (`activation_error`), coexistência, qualidade e limite de envio, quem conectou, datas de conexão, inscrição do app, registro (`registered_at`) e desconexão, pedidos e datas das sincronizações, último webhook, andamento da sincronização de templates (`templates_sync_requested_at`, `templates_synced_at`, `templates_sync_error`) |
| `whatsapp_conversations` | Conta, `bsuid` e `parent_bsuid`, `wa_id` e @usuário opcionais, nome do perfil, nome salvo na agenda do celular (`saved_name`), lead **ou** contato, última mensagem recebida (janela de 24h), não lidas e prévia |
| `whatsapp_messages` | Direção, tipo, origem (Admin, Celular, Contato), corpo, `wa_message_id` único, status (Enviando, Enviada, Entregue, Lida, Falhou, Recebida), erro, template e parâmetros, mídia (Active Storage e o ID da mídia na Meta), mensagem citada (`reply_to_wa_message_id`), reação (`reaction_to_wa_message_id` e `reaction_emoji`), autor, se veio do histórico, datas de envio, entrega, leitura, edição e exclusão, payload bruto |
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

## Permissões e auditoria

- Área `whatsapp` em `Role::AREAS`. O Administrador tem nível "full"; os outros perfis começam sem acesso e podem ser liberados na tela de permissões.
- Policies `WhatsappConversationPolicy`, `WhatsappMessagePolicy` e `WhatsappTemplatePolicy` seguem a matriz. `WhatsappAccountPolicy` exige nível "full" para conectar ou alterar um número.
- Templates: quem só lê a área vê a lista, a prévia e os detalhes; criar, editar e sincronizar (`sync?`) exigem escrita; excluir exige "full".
- `AuditLog` na conta (conexão, status) e nos templates, sem o token, sem o erro da ativação e sem os campos que a Meta atualiza sozinha. As conexões aparecem também nas atividades.

## Fases

0. ✅ **Protótipo**: telas em `docs/design/whatsapp`.
1. ✅ **Fundação**: configuração, tabelas, models, criptografia do token, área de permissão e policies, grupo no menu ainda como "em breve".
2. ✅ **Cliente da Graph API** em `app/services/whatsapp/` (Net::HTTP, sem gem nova): texto, mídia, template, marcar como lida, baixar mídia, templates, inscrição do app, troca do `code`, sincronizações.
3. ✅ **Webhook e processamento**: `/webhooks/whatsapp` fora do `ApplicationController`, assinatura `X-Hub-Signature-256`, job no Sidekiq, todos os campos inscritos, idempotente pelo `wa_message_id`, download da mídia.
4. ✅ **Conexão**: Embedded Signup v5 em Tecnologia → Integrações → WhatsApp, ativação em job (inscrição, registro ou sincronizações), validade do token.
5. ✅ **Templates**: lista, editor com prévia, criação, edição e exclusão na Meta, exemplo de mídia pelo upload retomável, sincronização pelo botão e diária.
6. **Conversas e tempo real**: tela de três colunas, Turbo Streams com ActionCable autenticado pelo Devise e Redis em desenvolvimento, campo de envio em Stimulus, contador no menu.
7. **Ligação com o CRM**: vincular ou criar lead, interação "WhatsApp" automática (uma por dia de conversa), cards no lead, na empresa e no contato, "Iniciar conversa".
8. **Avisos**: notificação por conversa (`Notification::KINDS`) e aviso do navegador com som.

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
- **Fase 8:** avisar o vencimento do token também pela central de notificações (hoje só na tela).
- **Fase 5 (resolvido):** a sincronização usa `WhatsappTemplate.attributes_from_meta`, como o webhook de status. O template criado direto no Gerenciador do WhatsApp entra na lista pela sincronização (botão ou rotina diária). Até lá, o status dele que chega pelo webhook fica só no log.
- **Fase 6:**
  - Gravar a mensagem enviada com o `wa_message_id` logo depois da resposta do envio. O status que chegar antes é reprocessado (3 novas tentativas, 15 s).
  - A caixa de entrada usa `with_messages` (a agenda cria conversas sem mensagem).
  - Mensagem apagada (`revoked_at`) aparece como "Mensagem apagada". Reação com emoji vazio não aparece.
- **Fase 7:** ao vincular conversa a lead ou contato pelo telefone, considerar a variação do nono dígito dos celulares brasileiros (com e sem o 9 depois do DDD).
