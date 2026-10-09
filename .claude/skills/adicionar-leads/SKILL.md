---
name: adicionar-leads
description: Cadastra leads em lote no Admin DevBatista (banco local ou de produção no Railway) a partir de uma lista colada pelo usuário — tabela, planilha, CSV ou texto solto com empresas, contatos, e-mails, telefones. Pergunta o que faltar para salvar (ambiente, origem, serviço, responsável, nome quando não há pessoa de contato), checa duplicados e grava com auditoria. Use quando o usuário pedir para adicionar, cadastrar, importar ou subir leads, prospects ou uma lista de prospecção no sistema.
---

# Adicionar leads

Cadastra uma lista de leads na tabela `leads` (model `Lead`, RF 6), sempre pelo model, para passar pelas validações e pela auditoria (`AuditLog` e `Activity`).

Tudo roda por [scripts/run.sh](scripts/run.sh), que executa [scripts/leads.rb](scripts/leads.rb) com `bin/rails runner`:

```bash
.claude/skills/adicionar-leads/scripts/run.sh <local|production> <payload.json>
```

- `local` roda na raiz do projeto, contra o banco de desenvolvimento.
- `production` roda via `railway ssh` no serviço ligado ao diretório (`railway status` mostra qual). Qualquer serviço com o código do app serve (web ou sidekiq).
- O aviso `Error retrieving instance profile credentials` é filtrado. Ele vem do SDK da AWS e não afeta os leads.

Grave o payload no diretório de scratchpad da sessão, nunca no repositório.

## Campos do lead

| Campo | Obrigatório | Observação |
| --- | --- | --- |
| `name` | sim | Pessoa de contato. Sem pessoa, ver pergunta "Nome" abaixo |
| `company_name` | não | Nome da empresa |
| `email` | não | Validado e salvo em minúsculas |
| `phone`, `whatsapp` | não | Texto livre, como veio da lista |
| `origin` | sim | `whatsapp`, `referral`, `site`, `diagnosis`, `meta_ads`, `google_ads`, `linkedin`, `outbound`, `other` |
| `service_id` | não | Serviço de interesse. Vazio aparece como "a definir" |
| `user_id` | sim | Responsável (usuário ativo) |
| `status` | sim (padrão `new`) | Só `new` (Novo Lead), `contacted` (Contato Realizado) ou `qualified` (Qualificado) |
| `entered_on` | sim (padrão hoje) | Data de entrada, `AAAA-MM-DD` |
| `notes` | não | Observações |
| `next_step`, `next_step_on` | não | Próximo passo e data |

Colunas da lista sem campo próprio (segmento, bairro, localização, site, Instagram etc.) vão para `notes`, uma por linha, no formato `Rótulo: valor`, na ordem da lista. Exemplo: `Segmento: Ar-condicionado\nLocalização ou atendimento: Jardim Novo Santo Amaro`.

## Passo a passo

### 1. Ler a lista

Mapeie cada coluna para um campo da tabela acima. Não invente dados: o que não está na lista fica vazio. Se uma coluna for ambígua (ex.: "Contato" pode ser pessoa, telefone ou e-mail), olhe os valores; se continuar ambígua, pergunte.

### 2. Ambiente

Se o usuário não disse, pergunte com `AskUserQuestion`: **Produção (Railway)** ou **Desenvolvimento local**.

### 3. Consulta

Monte o payload de consulta com os e-mails e nomes da lista e rode:

```json
{ "mode": "lookup", "emails": ["a@x.com"], "names": ["Empresa X"] }
```

A saída traz os usuários ativos, os serviços disponíveis, as origens, os status e os leads que já existem com o mesmo e-mail, nome ou empresa.

### 4. Perguntar o que falta

Use uma única chamada de `AskUserQuestion` (até 4 perguntas), só com o que a lista e a conversa não respondem:

- **Origem**: sugira a mais provável como "(Recommended)". Lista de prospecção ativa é `outbound`.
- **Serviço de interesse**: os serviços da consulta, mais a opção "A definir" (sem serviço).
- **Responsável**: os usuários ativos. Se só houver um, não pergunte; use-o e diga isso no resumo final.
- **Nome**, quando a lista não tem pessoa de contato:
  - "Nome da empresa": `name` = empresa e `company_name` vazio. Na lista aparece só a empresa. **Padrão já usado neste projeto.**
  - "Nome e Empresa iguais": os dois campos com a empresa.
  - "A identificar": `name` = "A identificar" e `company_name` = empresa.
- **Duplicados**, se a consulta encontrou algum: pular os já cadastrados (recomendado) ou criar mesmo assim.

Status, data de entrada e próximo passo só entram na pergunta se o usuário mencionou algo. Senão ficam `new`, hoje e vazio.

Se mais de 4 perguntas forem necessárias, priorize as obrigatórias (origem, responsável, nome) e faça uma segunda rodada.

### 5. Simular e gravar

Monte o payload de criação:

```json
{
  "mode": "create",
  "dry_run": true,
  "defaults": { "origin": "outbound", "user_id": "<uuid do usuário>", "service_id": "<uuid do serviço>", "status": "new" },
  "leads": [
    { "name": "Fran-coar", "email": "contatofrancoarcondicionado@gmail.com",
      "notes": "Segmento: Ar-condicionado\nLocalização ou atendimento: Jardim Novo Santo Amaro" }
  ]
}
```

- `defaults` vale para todos os leads; um campo dentro do lead sobrescreve o padrão.
- `defaults.user_id` também é o autor gravado na auditoria.
- Os ids são UUIDs (texto): copie-os da saída da consulta.
- Rode primeiro com `"dry_run": true`. O script cria tudo numa transação, mostra o resultado e desfaz. Se aparecer `ERRO`, nada foi gravado: corrija o payload e simule de novo.
- Com a simulação limpa, rode de novo com `"dry_run": false`. As respostas do passo 4 já valem como confirmação, inclusive em produção; só volte a perguntar se a simulação mudou algo (erro, duplicado novo).

A gravação é tudo ou nada: se um lead falhar, nenhum é salvo. Em produção, com listas acima de uns 100 leads, divida em lotes para não estourar o tamanho do comando do `railway ssh`.

### 6. Resumo

Diga quantos leads foram criados, a faixa de ids, os valores usados para origem, serviço, responsável, status e nome, o que foi para observações e quais duplicados foram pulados. Não repita a lista inteira se passar de uns 10 itens.
