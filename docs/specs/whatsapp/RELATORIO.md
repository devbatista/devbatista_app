# WhatsApp no Admin DevBatista

**Relatório do que foi feito · 27 a 29 de outubro de 2026**

## Resumo

O Admin DevBatista (admin.devbatista.com) agora conversa pelo WhatsApp Business. Ele usa a API oficial da Meta, com o mesmo número que continua funcionando no app do celular.

As mensagens chegam numa tela de conversas que atualiza sozinha. Cada conversa fica ligada ao lead ou ao contato certo do CRM. Dá para começar uma conversa a partir da ficha do cliente, e o Admin avisa quando chega mensagem nova.

O trabalho foi feito em 9 fases (de 0 a 8, a 7 dividida em duas), uma revisão por vez, e está todo em produção. A suíte de testes do Admin tem 575 testes automáticos, todos passando.

Falta só o uso real: conectar o número e testar com mensagens de verdade. O passo a passo está no fim deste documento.

## O que dá para fazer agora

### Conectar o número (Tecnologia → Integrações → WhatsApp)

- Conectar o número pela janela oficial da Meta (Embedded Signup), sem copiar nenhum código ou senha.
- Acompanhar a ativação: inscrição, registro do número e cópia dos contatos e do histórico do celular (até 180 dias).
- O app do WhatsApp Business no celular continua funcionando ao mesmo tempo (coexistência).
- O Admin avisa quando o acesso à Meta está para vencer e pede para conectar de novo.

### Templates (WhatsApp → Templates)

Template é a mensagem pré-aprovada pela Meta. Só ela pode abrir uma conversa ou retomar uma conversa parada há mais de 24 horas.

- Criar, editar e excluir templates com prévia de como o cliente vê, inclusive com imagem, vídeo ou documento no cabeçalho.
- Ver o status (aprovado, em análise, rejeitado) e o motivo da rejeição em português.
- Sincronizar com a Meta pelo botão e, automaticamente, todo dia.

### Conversas (WhatsApp → Conversas)

- Tela em três colunas: a lista de conversas, a conversa aberta e o painel do cliente. No celular, vira uma navegação de uma coluna por vez.
- Tudo em tempo real: mensagem nova, status de envio (enviando, enviada, entregue, lida) e contador de não lidas no menu, sem recarregar a página.
- Responder com texto, foto, áudio, vídeo ou documento; responder citando uma mensagem; reenviar o que falhou.
- **Janela de 24 horas**, a regra da Meta: mensagem livre só até 24 horas depois da última mensagem do cliente. Fora disso, só template. A tela mostra quanto tempo falta e troca sozinha para o modo template.
- Busca por nome, telefone ou @usuário, e filtros: não lidas, leads, clientes, sem vínculo e janela aberta.
- Abrir a conversa marca como lida (os dois tiques azuis aparecem para o cliente).

### Ligação com o CRM

- **Vínculo automático:** quando chega mensagem de um número que está num lead ou contato, a conversa se liga sozinha a ele. Isso vale também quando o número está gravado com ou sem o nono dígito. Se houver mais de um cadastro com o mesmo número, o Admin mostra as opções e a pessoa escolhe.
- **Painel do cliente na conversa:** etapa no funil, propostas em aberto, próximo passo, responsável e últimas interações.
- **Sem cadastro:** "Criar lead", já preenchido com o nome, o telefone e as primeiras mensagens, ou "Vincular" a um lead ou contato existente.
- **Desvincular:** a conversa desvinculada à mão não volta a se ligar sozinha.
- **Interação automática:** cada dia de conversa vira uma interação "WhatsApp" no lead ou na oportunidade, só com a contagem ("4 recebidas, 2 enviadas"), nunca com o conteúdo.

### Começar uma conversa

- Botão "Nova conversa" na tela de conversas e "Iniciar conversa no WhatsApp" na ficha do lead, na empresa e na lista de contatos.
- O primeiro contato é sempre por template aprovado, e o nome do cliente já vem preenchido nas variáveis.
- Se o cadastro não tem WhatsApp, o Admin pede o número e oferece salvar no cadastro.

### Cards no CRM

- **Ficha do lead:** as últimas mensagens da conversa, a janela de 24 horas e o botão "Abrir conversa", ou "Iniciar conversa" se ainda não houver conversa.
- **Visão 360º da empresa:** cada contato com a conversa mais recente e as não lidas.

### Avisos

- **Central de notificações (sino do topo):** um aviso por conversa ("Henrique · 3 mensagens novas"), atualizado em tempo real. Ele some quando a conversa é aberta ou respondida pelo celular.
- **Aviso do navegador com som:** chega mesmo com o Admin em outra aba ou em outra tela. Para ligar, use "Ativar avisos" na tela de conversas. O som liga e desliga no menu do usuário.
- **Aviso do acesso à Meta vencendo:** 7 dias antes e no dia.

## Como foi feito

| Fase | O que entregou | PR | Data |
| --- | --- | --- | --- |
| 0 · Protótipo | As telas desenhadas antes de programar | [#4](https://github.com/devbatista/devbatista_app/pull/4) | 27/10 |
| 1 · Fundação | Configuração, tabelas do banco, criptografia do acesso à Meta e permissões | [#5](https://github.com/devbatista/devbatista_app/pull/5) | 27/10 |
| 2 · Comunicação com a Meta | Envio de mensagens, mídia, templates e marcação de lida pela API da Meta | [#6](https://github.com/devbatista/devbatista_app/pull/6) | 27/10 |
| 3 · Recebimento | Recebimento das mensagens e dos status, com conferência da assinatura da Meta e download da mídia | [#7](https://github.com/devbatista/devbatista_app/pull/7) | 27/10 |
| 4 · Conexão | Conectar o número pela janela da Meta e acompanhar a ativação | [#8](https://github.com/devbatista/devbatista_app/pull/8) | 28/10 |
| 5 · Templates | Criar, editar, excluir e sincronizar templates | [#9](https://github.com/devbatista/devbatista_app/pull/9) | 28/10 |
| 6 · Conversas | A tela de conversas em tempo real e o envio | [#10](https://github.com/devbatista/devbatista_app/pull/10) | 28/10 |
| 7a · Vínculo com o CRM | Vínculo automático, painel do cliente, criar lead e interação automática | [#11](https://github.com/devbatista/devbatista_app/pull/11) | 28/10 |
| 7b · Iniciar conversa | "Nova conversa", cards no CRM e variáveis já preenchidas | [#12](https://github.com/devbatista/devbatista_app/pull/12) | 28/10 |
| 8 · Avisos | Central de notificações, sino em tempo real e aviso do navegador com som | [#13](https://github.com/devbatista/devbatista_app/pull/13) | 29/10 |
| Correção | Erro no log quando a sessão expira com o Admin aberto, achado na verificação de produção | [#14](https://github.com/devbatista/devbatista_app/pull/14) | 29/10 |

**Como cada fase foi conduzida:**
- um PR por fase, revisado antes de ir para a main;
- testes automáticos e verificação de código e de segurança (rubocop e brakeman) ao final de cada fase;
- ajustes pedidos na revisão aplicados antes do merge.

Ao todo foram cerca de 13 mil linhas, contando testes e documentação.

## Segurança e privacidade

- **Acesso à Meta protegido:** o token fica criptografado no banco e nunca aparece em log, tela ou auditoria. Nenhuma senha ou chave fica no código: tudo vem das variáveis do Railway.
- **Mensagens protegidas nos logs:** o conteúdo das mensagens, os telefones e os nomes não vão para os logs nem para as tarefas em segundo plano, que levam só identificadores.
- **Mídia com permissão:** fotos e documentos só abrem com permissão, por um link temporário de 5 minutos, nunca por um link público permanente.
- **Conteúdo do cliente seguro:** o que o cliente manda é exibido de forma segura. Links e nomes de arquivo são tratados para não executar nada no navegador.
- **Recebimento autêntico:** o Admin confere a assinatura da Meta em cada mensagem recebida e descarta o que não for dela.
- **Sem mensagem duplicada:** se a Meta não confirmar um envio, o Admin não tenta de novo sozinho, porque a mensagem pode ter chegado. Ele avisa e deixa a pessoa decidir.
- **Permissões:** a área WhatsApp segue a tela de permissões do Admin. Na v1, só o administrador usa. Os dados do CRM no painel seguem a permissão de cada área.

## Situação em produção (29/10)

- Todas as fases estão publicadas em admin.devbatista.com, no serviço web e no Sidekiq.
- O banco está atualizado, com todas as migrations aplicadas.
- Ainda não há número conectado nem conversa: o uso real começa na conexão.

## Próximos passos: o primeiro uso real

1. **Conferir as variáveis no Railway:**
   - `META_APP_ID`, `META_APP_SECRET`, `WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID`, `WHATSAPP_WEBHOOK_VERIFY_TOKEN`;
   - as três `ACTIVE_RECORD_ENCRYPTION_*`. Guarde uma cópia delas no cofre de senhas: perder essas chaves obriga a conectar o número de novo.
2. **Conectar o número** em Tecnologia → Integrações → WhatsApp e acompanhar a ativação até "Conectado".
3. **Templates:** sincronizar, ou criar um, e esperar a aprovação da Meta.
4. **Conversas:**
   - receber uma mensagem e ver aparecer sem recarregar;
   - responder com texto e com anexo;
   - enviar um template e acompanhar os tiques.
5. **CRM:**
   - ver a conversa se ligar sozinha a um lead com o mesmo número;
   - testar "Criar lead", "Vincular" e "Iniciar conversa" pela ficha.
6. **Avisos:** seguir o roteiro de 8 passos da seção "Avisos" da documentação técnica. Os pontos principais:
   - ativar os avisos;
   - receber mensagem em outra aba e ouvir o som;
   - clicar no aviso e ver a conversa abrir.

**Pontos que só o uso real confirma**, porque a documentação da Meta não deixa claro:
- O formato da imagem, do vídeo ou do documento no cabeçalho dos templates, no envio.
- Se o acesso conectado pela janela da Meta tem data de validade, e qual.
- A forma do número (com ou sem o nono dígito) que a Meta devolve ao começar uma conversa pelo número do cadastro.
- Detalhes da janela de conexão da Meta, que só funciona no domínio de produção.

Se algum deles se comportar diferente do esperado, o ajuste é pontual e está mapeado na documentação técnica.

## Fora desta versão

- Aviso com o Admin fechado (notificação push).
- Sugestão de resposta por IA (virá do agente SDR, sem enviar nada ao cliente sem revisão).
- Grupos e chamadas.
- Liberar o WhatsApp para a equipe comercial: autor e responsável por usuário já estão preparados.

## Onde está o resto

- **Documentação técnica completa:** [`docs/specs/whatsapp/README.md`](README.md), com as decisões, a configuração, cada fase em detalhe, as permissões e os pontos em aberto.
- **Protótipo das telas:** [`docs/design/whatsapp`](../../design/whatsapp/README.md).
