# Leads do site — webhook

Novembro de 2026 · Os formulários do devbatista.com (Diagnóstico Tecnológico, e-book e formulário de contato) viram leads no Comercial, no lugar do HubSpot. Evolução do [RF 6 · Leads](../admin-devbatista-mvp/04-requisitos-funcionais/02-comercial.md).

**O Admin é o único responsável pelos e-mails dos leads do site.** O site só grava o envio no JSONL dele e repassa os dados para o webhook; não manda mais e-mail pelo SES. O aviso ao Rafael (diagnóstico e contato) e a entrega do e-book ao visitante saem do Admin. Ver [E-mails](#e-mails).

## Decisões

| Tema | Decisão |
| --- | --- |
| Caminho | Navegador → PHP do site → `POST admin.devbatista.com/webhooks/site-leads`, servidor a servidor. O token não vai para o navegador |
| Autenticação | `Authorization: Bearer <SITE_LEADS_TOKEN>` (`config.x.site_leads.token`; no site, `crm_token`). Sem token configurado no Admin, tudo é recusado e o erro vai para o log |
| Código | `Webhooks::SiteLeadsController < ActionController::API` (fora do login, do Pundit e do CSRF) e `SiteLeadCapture` (`app/services/site_lead_capture.rb`) |
| Responsável | O administrador ativo mais antigo. Sem nenhum, o envio é recusado (422) |
| Um lead por pessoa | O envio completa o lead **em aberto** (Novo, Contato Realizado, Qualificado) mais recente com o mesmo e-mail **ou** o mesmo WhatsApp, em vez de abrir outro. Lead perdido ou convertido não é reaberto: o envio abre um lead novo |
| Edição à mão | Só os campos vazios são preenchidos. O nome só é trocado quando ainda é o e-mail provisório do e-book. `details` se soma às observações, separado por uma linha em branco |

## Requisição

`POST /webhooks/site-leads`, `Content-Type: application/json`.

| Campo | Tipo | Uso |
| --- | --- | --- |
| `source` | string | Tipo de envio: `diagnosis`, `ebook` ou `contact` |
| `site_id` | string | Id do envio no JSONL do site. Vai para `leads.external_id` (único) quando o envio abre lead novo |
| `name` | string | Nome da pessoa |
| `company` | string | Empresa → `company_name` |
| `email` | string | E-mail, guardado em minúsculas |
| `phone` | string | DDD + número, sem o 55 (`11999990000`). Vira o WhatsApp do lead no formato `(11) 99999-0000` (`Setting.format_phone`) |
| `summary` | string | Uma linha, para a nota na linha do tempo |
| `details` | string | Texto completo, somado às observações do lead |
| `tier` | string | Só no diagnóstico: `frio`, `morno` ou `quente` |
| `need` | string | Só no contato: a necessidade marcada (ver [Serviço de interesse](#serviço-de-interesse)) |
| `segment` | string | Só no contato, opcional: o segmento já em rótulo (`Contabilidade`). Só aparece no e-mail do aviso; sem ele, vale a linha `Segmento: ...` do `details` |
| `consent` | boolean | Só no contato, opcional. Não muda nada no lead além do registro: vira a linha `Consentimento de contato: sim` (ou `não`) no fim do `details` nas observações |

Exemplo do formulário de contato:

```json
{
  "source": "contact", "site_id": "abc123", "name": "Maria Souza", "company": "Escritório X",
  "email": "", "phone": "11999990000", "need": "whatsapp_ia", "consent": true,
  "summary": "Contato pelo site: Atendimento com IA no WhatsApp · Contabilidade",
  "details": "Segmento: Contabilidade\nMensagens por mês: 300 a 1.000\n..."
}
```

## Tipos de envio

| `source` | Origem do lead | Obrigatórios | Nota padrão (sem `summary`) | Aviso ao responsável |
| --- | --- | --- | --- | --- |
| `diagnosis` | Diagnóstico | `name`, `email` | "Fez o Diagnóstico Tecnológico pelo site" | "Novo lead do site: <lead>" ou "<lead> fez o Diagnóstico Tecnológico no site", com " · potencial <tier>". `warn` se quente, senão `info` |
| `ebook` | Site | `email` | "Baixou o e-book pelo site" | Nenhum. O visitante recebe o e-mail com o link do e-book |
| `contact` | Site | `name`, `phone` | "Enviou o formulário de contato pelo site" | "Novo contato do site: <lead>" ou "<lead> enviou o formulário de contato". Sempre `warn`: quem manda o formulário está pronto para conversar |

- E-mail que vier, em qualquer tipo, precisa ser válido. No contato ele é opcional (`""` é aceito).
- O e-book chega só com o e-mail, que fica de nome provisório até um envio com nome.
- A origem é a do envio que **abriu** o lead: o diagnóstico que completa um lead do e-book não troca a origem.
- Cada envio vira uma interação do tipo nota, com a data do dia e o responsável do lead.
- O aviso é a notificação `site_lead` (sino e e-mail, ligado por padrão), com link para o lead.

### Serviço de interesse

Só no contato, e só se o lead ainda não tiver serviço. O serviço é buscado no catálogo **pelo nome**, não por id:

| `need` | Serviço |
| --- | --- |
| `whatsapp_ia` | Inteligência Artificial |
| `automacao_ia` | Automação/RPA |
| `ia_sistemas` | Inteligência Artificial |
| `sob_medida` | Desenvolvimento de sistemas |
| `manutencao` | Manutenção |
| `agencia`, `nao_sei` ou outro | Fica vazio |

Se o serviço não existir no catálogo (renomeado ou excluído), o lead segue sem ele, sem erro.

### Próximo passo

No contato, se o lead não tiver próximo passo: "Responder o contato do site pelo WhatsApp", com a data e a hora da chegada. Entra em Comercial → Próximos passos e na tool `proximos_passos` do MCP.

## E-mails

Todos saem pelo e-mail do Admin (Amazon SES, interface SMTP, `config/environments/production.rb`), pelo Sidekiq (`deliver_later`).

### Aviso ao responsável

O e-mail da notificação `site_lead` (`NotificationMailer#alert`, template `site_lead`), para **todo** contato e **todo** diagnóstico, de qualquer potencial. O site mandava só os diagnósticos morno e quente; agora o frio também chega, e o potencial vai no assunto. O e-book não avisa ninguém.

- **Assunto:** `[Admin DevBatista] ` + o título do aviso, por exemplo `[Admin DevBatista] Novo lead do site: Clínica Sorriso · Ana Souza · potencial quente`.
- **Corpo:** nome, WhatsApp (com link `wa.me`), e-mail, empresa, origem do envio (Diagnóstico Tecnológico ou Formulário de contato), potencial (só diagnóstico), o que precisa (só contato, com o rótulo do formulário), serviço de interesse, segmento, o resumo de uma linha, o envio completo (`details`, com o consentimento) e o botão "Abrir o lead". Os dados do lead são lidos do próprio lead (já completado); a origem, o potencial, o que precisa, o segmento, o resumo e o `details` são os do envio.
- **Quem recebe:** o responsável do lead. O e-mail sai se as duas chaves estiverem ligadas: a preferência "Leads do site" da pessoa (Notificações → Preferências de e-mail; ligada por padrão) e "Permitir envio de alertas por e-mail" (Administração → Configurações, `Setting[:email_enabled]`). Quem já salvou as preferências mantém a escolha gravada: salvar a tela grava todos os tipos, então quem salvou com "Leads do site" desmarcado precisa ligar à mão.

### E-book

`EbookMailer#download`, para quem pediu o e-book, a cada pedido: quem pede duas vezes recebe de novo, e o lead continua um só (o envio completa o lead em aberto).

- **Conteúdo:** assunto "Seu e-book chegou: onde a TI drena o lucro da sua empresa", texto e HTML copiados do site (`ebook_email_text()` e `ebook_email_html()` em `api/ebook.php`), sem o layout do Admin. O link é o `EBOOK_DOWNLOAD_URL`.
- **Remetente:** o endereço pessoal do Rafael (`EBOOK_EMAIL_FROM`, padrão `rafael@devbatista.com`; nome `EBOOK_EMAIL_FROM_NAME`, padrão `Rafael Batista`), sem Reply-To: responder cai direto nele. O endereço precisa ser identidade verificada no SES (o domínio `devbatista.com` verificado cobre).
- **Não depende** de "Permitir envio de alertas por e-mail": essa chave é dos alertas internos. O e-book é entrega ao visitante, como a proposta e a fatura.
- **Resposta ao site:** o webhook só responde 201/200 com o lead salvo **e** o e-mail aceito para envio (enfileirado no Sidekiq). Sem `EBOOK_DOWNLOAD_URL` (ou com valor que não seja `http(s)://`), ou se a fila recusar, o lead fica salvo e a resposta é 503 `{"errors": ["ebook_unavailable"]}`, com o motivo no log (`[SiteLeads]`). O site mostra a mensagem de falha e o visitante pode tentar de novo, o que completa o mesmo lead. Uma falha do SES depois de enfileirado não volta para o site: o Sidekiq tenta de novo.

### Variáveis

| Variável | Uso |
| --- | --- |
| `EBOOK_DOWNLOAD_URL` | Link do PDF do e-book (`config.x.ebook.download_url`). Obrigatória para entregar o e-book; sem ela, o envio do e-book responde 503 |
| `EBOOK_EMAIL_FROM` | Remetente do e-book. Padrão `rafael@devbatista.com` |
| `EBOOK_EMAIL_FROM_NAME` | Nome do remetente do e-book. Padrão `Rafael Batista` |

O aviso ao responsável não tem variável nova: usa o `MAILER_SENDER` e as credenciais do SES (`SES_*`) que os outros alertas já usam.

## Respostas

| Status | Quando | Corpo |
| --- | --- | --- |
| 201 | Lead criado | `{ "id": "<uuid>", "created": true }` |
| 200 | Lead em aberto completado | `{ "id": "<uuid>", "created": false }` |
| 401 | Token errado, ausente ou não configurado no Admin | vazio |
| 422 | Dados inválidos ou nenhum administrador ativo | `{ "errors": ["..."] }` |
| 503 | E-book: lead salvo, mas o e-mail não pôde ser enviado (`EBOOK_DOWNLOAD_URL` faltando ou fila fora do ar) | `{ "errors": ["ebook_unavailable"] }` |

O envio vazio é o teste de conexão do site (`/api/health.php?check=crm`): o 422 prova que o token passou.

## Testes

`spec/requests/site_leads_webhook_spec.rb`: os três tipos de envio, e-book completado pelo diagnóstico, edição à mão preservada, contato sem e-mail, deduplicação por e-mail e por telefone (o mais recente em aberto; perdido e convertido abrem outro), `need` → serviço (inclusive serviço fora do catálogo), nota padrão, próximo passo, avisos, 401 e 422. E-mails: aviso do diagnóstico (qualquer potencial, nível no assunto, dados no corpo) e do contato, nenhum aviso no e-book, preferência e `email_enabled` desligados respeitados, e-book com o link e o remetente certos e sem Reply-To, reenvio sem duplicar o lead, 503 sem `EBOOK_DOWNLOAD_URL` e com a fila fora do ar. Pré-visualização em `/rails/mailers` (`NotificationMailerPreview#site_lead_*` e `EbookMailerPreview`).
