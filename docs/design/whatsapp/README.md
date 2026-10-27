# WhatsApp: protótipo

Telas da integração com o WhatsApp Business (Cloud API da Meta). Elas seguem o [DESIGN-SYSTEM](../DESIGN-SYSTEM.md). Os dados são ilustrativos e "agora" é 17/09/2026 11:24, como no resto do protótipo.

## Telas

| Tela | Arquivo | Estados para revisar |
| --- | --- | --- |
| Conversas (3 colunas) | `conversas.html` | `?c=henrique` (lead, janela aberta), `?c=beatriz` (janela fechada, template com falha), `?c=lu` (sem vínculo, sem telefone), `?c=camila` (janela fechando) |
| Templates | `templates.html` | "Novo template", "Editar" e "Corrigir" (rejeitado) abrem o editor com prévia |
| Conexão | `conexao.html` | No menu fica em Tecnologia → Integrações. "Conectar WhatsApp" mostra o andamento; "Desconectar" explica o caminho pelo celular |
| Card no lead | `../comercial/lead.html` | Seletor: com conversa, sem conversa, sem WhatsApp cadastrado |
| Card na empresa | `../clientes/empresa.html` (aba Resumo) | Seletor: com conversas, sem conversa |
| Contato | `../clientes/contatos.html`, ação "WhatsApp" | Marcos Andrade (com conversa), Paulo Reis (sem conversa), Rodrigo Nunes (sem WhatsApp cadastrado) |

O seletor tracejado "Protótipo · card WhatsApp" só existe no protótipo (`data-proto-scope`, no `app.js`). No sistema, o estado vem dos dados.

O diálogo "Iniciar conversa no WhatsApp" é o mesmo no lead, na empresa e no contato (`../assets/wa-iniciar.js`). Ele usa o número do cadastro e, sem número, avisa e pede o número, com a opção de salvar no cadastro. O primeiro contato é sempre por template aprovado.

## Regras para a implementação

- **Número e nome da conta vêm do sistema.** O `+55 11 97070-2026` e o nome "DevBatista" do protótipo são exemplos. Na implementação, o número exibido em toda parte (conexão, cards, rodapés, seletores de conta, diálogos) vem da conta conectada salva no banco, nunca de texto fixo no código.
- **Na v1, só o administrador usa o WhatsApp.** Os outros usuários do protótipo (Ana Souza, Bruno Lima…) aparecem como autor de mensagem, responsável ou opção de seleção só como exemplo. Responsável e autor por usuário são preparação para quando o acesso for liberado ao Comercial, fora da v1. Na v1, o autor das mensagens enviadas é o administrador logado, e o "Responsável" do painel é o dono do lead ou da oportunidade, que já existe no Comercial.
- **Desconexão em coexistência é feita no celular.** A Meta não permite remover pela API um número usado no app e na Cloud API ao mesmo tempo, então o Admin não tem botão para desconectar: ele explica o caminho no app WhatsApp Business (Configurações → Conta → Plataforma comercial → Desconectar conta). Quando a Meta envia `account_update` com `PARTNER_REMOVED`, o sistema marca a conta como desconectada e mantém as conversas para consulta, sem envio.
- **Aviso do navegador ("Ativar avisos").** Aparece até a pessoa escolher "Ativar avisos" ou "Agora não" e depois não volta. No protótipo a escolha fica no `localStorage` (chave `wa-avisos`; apague a chave para ver o aviso de novo). Na implementação, a escolha fica numa preferência do usuário. Se o navegador negar a permissão (`Notification.permission === "denied"`), aparece só uma linha discreta explicando como reativar pelo cadeado da barra de endereço.
- **Janela de 24h.** Com a janela fechada não há campo de texto nem anexo, só "Responder com template". Mensagens enviadas pelo app do celular não abrem nem estendem a janela.
