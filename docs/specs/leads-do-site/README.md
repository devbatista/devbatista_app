# Leads do site — webhook

Novembro de 2026 · Os formulários do devbatista.com (Diagnóstico Tecnológico, e-book e formulário de contato) viram leads no Comercial, no lugar do HubSpot. Evolução do [RF 6 · Leads](../admin-devbatista-mvp/04-requisitos-funcionais/02-comercial.md).

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
| `ebook` | Site | `email` | "Baixou o e-book pelo site" | Nenhum |
| `contact` | Site | `name`, `phone` | "Enviou o formulário de contato pelo site" | "Novo contato do site: <lead>" ou "<lead> enviou o formulário de contato". Sempre `warn`: quem manda o formulário está pronto para conversar |

- E-mail que vier, em qualquer tipo, precisa ser válido. No contato ele é opcional (`""` é aceito).
- O e-book chega só com o e-mail, que fica de nome provisório até um envio com nome.
- A origem é a do envio que **abriu** o lead: o diagnóstico que completa um lead do e-book não troca a origem.
- Cada envio vira uma interação do tipo nota, com a data do dia e o responsável do lead.
- O aviso é a notificação `site_lead` (sino; e-mail desligado por padrão), com link para o lead.

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

## Respostas

| Status | Quando | Corpo |
| --- | --- | --- |
| 201 | Lead criado | `{ "id": "<uuid>", "created": true }` |
| 200 | Lead em aberto completado | `{ "id": "<uuid>", "created": false }` |
| 401 | Token errado, ausente ou não configurado no Admin | vazio |
| 422 | Dados inválidos ou nenhum administrador ativo | `{ "errors": ["..."] }` |

O envio vazio é o teste de conexão do site (`/api/health.php?check=crm`): o 422 prova que o token passou.

## Testes

`spec/requests/site_leads_webhook_spec.rb`: os três tipos de envio, e-book completado pelo diagnóstico, edição à mão preservada, contato sem e-mail, deduplicação por e-mail e por telefone (o mais recente em aberto; perdido e convertido abrem outro), `need` → serviço (inclusive serviço fora do catálogo), nota padrão, próximo passo, avisos, 401 e 422.
