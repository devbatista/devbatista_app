# WhatsApp Business no Admin DevBatista — v1

Outubro de 2026 · Integração com a **Cloud API da Meta** para conversar pelo WhatsApp de dentro do Admin, ligado aos leads e contatos. A DevBatista é Tech Provider na Meta (app "DevBatista Admin", portfólio DevBatista), e o primeiro número é o da própria DevBatista, em **coexistência** com o app WhatsApp Business do celular. O protótipo está em [`docs/design/whatsapp`](../../design/whatsapp/README.md).

## Decisões

| Tema | Decisão |
| --- | --- |
| Contas | Várias contas conectadas (uma por número). Na v1, o número da DevBatista; depois, números de clientes |
| Conexão | Embedded Signup da Meta, em Tecnologia → Integrações. O token fica criptografado (Active Record Encryption) e fora da auditoria |
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
- **Embedded Signup.** O `code` devolvido vale 30 segundos (a troca por token acontece na própria requisição). As versões 2 e 3 foram descontinuadas em 15/10/2026: a configuração `featureType: "whatsapp_business_app_onboarding"` com `sessionInfoVersion: 3` precisa ser confirmada para a versão atual (v4/v5) na Fase 4.

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
| `whatsapp_accounts` | Portfólio, WABA, `phone_number_id` (único), número exibido, nome verificado, token criptografado, status (Conectando, Conectado, Desconectado), coexistência, qualidade e limite de envio, quem conectou, datas de conexão, inscrição do app e desconexão, pedidos e datas das sincronizações, último webhook |
| `whatsapp_conversations` | Conta, `bsuid` e `parent_bsuid`, `wa_id` e @usuário opcionais, nome do perfil, lead **ou** contato, última mensagem recebida (janela de 24h), não lidas e prévia |
| `whatsapp_messages` | Direção, tipo, origem (Admin, Celular, Contato), corpo, `wa_message_id` único, status (Enviando, Enviada, Entregue, Lida, Falhou, Recebida), erro, template e parâmetros, mídia (Active Storage e o ID da mídia na Meta), mensagem citada (`reply_to_wa_message_id`), reação (`reaction_to_wa_message_id` e `reaction_emoji`), autor, se veio do histórico, datas de envio, entrega e leitura, payload bruto |
| `whatsapp_templates` | Conta, ID na Meta, nome, idioma, categoria, status, componentes (formato da Graph API), nº de variáveis do cabeçalho e do corpo, motivo de rejeição |

Garantias no banco: o BSUID e o telefone são únicos por conta; a conversa precisa de BSUID ou telefone e não liga lead e contato ao mesmo tempo (check constraints); o `wa_message_id` é único, o que torna o processamento dos webhooks idempotente.

Respostas e reações: a resposta guarda o `context.id` da mensagem citada em `reply_to_wa_message_id`. A reação (tipo `reaction`) guarda o alvo e o emoji e aparece **sobre a mensagem reagida**, não como mensagem nova: `WhatsappMessage.timeline` exclui as reações e `#reactions` lista as de cada mensagem. Emoji vazio é a pessoa removendo a reação.

O BSUID fica em `bsuid`, e não em `user_id`, porque nesta base `user_id` é sempre o usuário dono do registro: a `ApplicationPolicy` usa essa coluna no nível de permissão "own".

## Permissões e auditoria

- Área `whatsapp` em `Role::AREAS`. O Administrador tem nível "full"; os outros perfis começam sem acesso e podem ser liberados na tela de permissões.
- Policies `WhatsappConversationPolicy`, `WhatsappMessagePolicy` e `WhatsappTemplatePolicy` seguem a matriz. `WhatsappAccountPolicy` exige nível "full" para conectar ou alterar um número.
- `AuditLog` na conta (conexão, status) e nos templates, sem o token e sem os campos que a Meta atualiza sozinha. As conexões aparecem também nas atividades.

## Fases

0. ✅ **Protótipo**: telas em `docs/design/whatsapp`.
1. ✅ **Fundação**: configuração, tabelas, models, criptografia do token, área de permissão e policies, grupo no menu ainda como "em breve".
2. **Cliente da Graph API** em `app/services/whatsapp/` (Net::HTTP, sem gem nova): texto, mídia, template, marcar como lida, baixar mídia, templates, inscrição do app, troca do `code`, sincronizações.
3. **Webhook e processamento**: `/webhooks/whatsapp` fora do `ApplicationController`, assinatura `X-Hub-Signature-256`, job no Sidekiq, todos os campos inscritos, idempotente pelo `wa_message_id`.
4. **Conexão**: Embedded Signup em Tecnologia → Integrações.
5. **Templates**: tela, criação e edição na Meta, sincronização.
6. **Conversas e tempo real**: tela de três colunas, Turbo Streams com ActionCable autenticado pelo Devise e Redis em desenvolvimento, campo de envio em Stimulus, contador no menu.
7. **Ligação com o CRM**: vincular ou criar lead, interação "WhatsApp" automática (uma por dia de conversa), cards no lead, na empresa e no contato, "Iniciar conversa".
8. **Avisos**: notificação por conversa (`Notification::KINDS`) e aviso do navegador com som.

## Pontos em aberto

- **Fase 2:** confirmar os endpoints de troca do `code` e de `subscribed_apps` para Tech Provider.
- **Fases 2 e 5:** a Meta devolve categoria e status de template em maiúsculas (`UTILITY`, `APPROVED`, `IN_APPEAL`…); converter para os enums (`utility`, `approved`, `in_appeal`) na sincronização e no webhook de status. Vale o mesmo para a qualidade do número (`GREEN` → `green`).
- **Fase 3:**
  - Buscar a conversa por BSUID **e** por telefone e completar o campo que faltar, para não duplicar quem já existia (por exemplo, a conversa criada pelo telefone ao iniciar com template e a resposta que chega com o BSUID).
  - Tratar `ActiveRecord::RecordNotUnique` quando dois webhooks criarem a mesma conversa ao mesmo tempo: recarregar e seguir.
  - Processar reações (sobre a mensagem reagida; nova reação da mesma pessoa substitui a anterior) e respostas citadas (`context.id`).
- **Fase 4:** confirmar a configuração do Embedded Signup para a versão atual (v4/v5).
- **Fase 7:** ao vincular conversa a lead ou contato pelo telefone, considerar a variação do nono dígito dos celulares brasileiros (com e sem o 9 depois do DDD).
