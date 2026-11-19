# Faturas — v1

Novembro de 2026 · Área do Financeiro para cobrar o cliente. O ciclo é: **emito a fatura → o cliente paga → emito a nota fiscal na contabilidade e registro em Notas fiscais**. Até aqui o sistema tinha as receitas (contas a receber) e as notas fiscais, mas nenhum documento de cobrança para mandar ao cliente.

Antes desta entrega, o model `Invoice` guardava a nota fiscal. Ele passou a se chamar `FiscalInvoice` (PR #36), e o nome `Invoice` ficou para a fatura.

## Decisões

| Tema | Decisão |
| --- | --- |
| Composição | Uma fatura **agrupa várias receitas** do mesmo cliente (ex.: hospedagem + manutenção + suporte do mês). Cada receita fica em no máximo uma fatura ativa |
| Criação | **Manual.** A tela de faturas lista as receitas em aberto ainda sem fatura, por cliente; eu escolho as receitas e crio. Sem rotina automática |
| Pagamento | **Pix ou transferência, confirmado à mão.** A fatura traz o Pix (QR Code e copia e cola, BR Code estático com o valor e o número da fatura) e os dados bancários. Sem gateway: cobrança automática continua na V1.1 |
| Pagamento parcial | **Não.** Registrar pagamento marca a fatura e todas as receitas dela como pagas, na mesma data e pelo valor de cada receita. Se o cliente pagar diferente, cancelo e emito outra |
| Envio | E-mail com o PDF anexado, WhatsApp (template aprovado, com as variáveis preenchidas), link público sem login e PDF para baixar |
| Numeração | `FAT-2026-0001`: sequencial que reinicia a cada ano. O número só é dado na emissão, então rascunho excluído não deixa buraco |
| Lembretes | Fora da v1. Só o aviso interno quando a fatura vence |
| Menu | Financeiro → **Faturas** (`/finance/invoices`), depois de Contas a receber |
| Usuários | Área `financeiro` da matriz de permissões, como as receitas e as notas fiscais |

## Ciclo de vida

| Status | O que significa | O que dá para fazer |
| --- | --- | --- |
| Rascunho | Montando: cliente, receitas, vencimento, contato, observações | Editar, excluir, emitir |
| Emitida | Número dado, conteúdo travado. Pode ser enviada quantas vezes for preciso | Enviar (e-mail, WhatsApp, link, PDF), registrar pagamento, cancelar |
| Vencida | Emitida com o vencimento já passado. Não é gravada: é calculada (`due_on < hoje`) | O mesmo da Emitida |
| Paga | Pagamento registrado | Registrar a nota fiscal das receitas |
| Cancelada | Fora da cobrança. As receitas voltam a ficar sem fatura e podem entrar em outra | — |

- **Na emissão**, o vencimento de cada receita passa a ser o da fatura, para Contas a receber, o dashboard e o aviso de atraso seguirem a fatura.
- **Itens.** A fatura guarda uma cópia de cada receita (descrição, competência e valor) em `invoice_items`. O documento emitido não muda se a receita for editada depois, e a fatura cancelada continua mostrando o que cobrava.
- **Receitas aceitas:** do mesmo cliente, em aberto (prevista, pendente ou vencida) e sem outra fatura ativa.
- **Enviada e visualizada** são datas (`sent_at`, `viewed_at`), não status. A primeira abertura do link público por quem não está logado marca `viewed_at`.

## Dados

```
invoices
  company_id, contact_id (opcional; padrão: contato principal)
  year, number            # nulos no rascunho; FAT-<year>-<number 4 dígitos>
  status                  # draft, issued, paid, cancelled
  due_on, issued_on, paid_on, sent_at, viewed_at
  total_cents             # soma dos itens
  client_notes            # observações que vão na fatura
  notes                   # anotação interna
  cancellation_reason

invoice_items
  invoice_id, receivable_id, description, competence, amount_cents, position

receivables.invoice_id    # fatura ativa da receita (nulo quando a fatura é cancelada)
```

## Pix e dados bancários

Configurações → Financeiro, card "Faturas":

- `pix_key`: chave Pix, com o tipo escolhido na tela (CNPJ, CPF, celular, e-mail ou aleatória). A máscara segue o tipo, e a chave é guardada no formato do banco: CNPJ e CPF só com dígitos, celular com +55, e-mail e aleatória em minúsculas. CNPJ e CPF têm os dígitos verificadores conferidos no navegador e no servidor (`PixKey`), porque com um dígito errado o app do banco responde "chave inexistente";
- `pix_receiver_name`: nome do recebedor no Pix (até 25 caracteres; padrão: razão social);
- `pix_receiver_city`: cidade do recebedor (até 15 caracteres);
- `bank_details`: dados para transferência, em texto livre.

O QR Code é o BR Code estático do Banco Central (EMV, com CRC16), com o valor e o identificador da transação (`FAT20260001`). Sem chave Pix configurada, a fatura mostra só os dados bancários.

## Envio

- **E-mail.** Como a proposta: PDF anexado, botão "Ver fatura" (link público), resposta para quem enviou e cópia guardada em Documentos (tipo "Fatura"). Marca `sent_at`.
- **WhatsApp.** Abre o "Iniciar conversa" com o contato da fatura. As variáveis nomeadas conhecidas vêm preenchidas: `fatura`/`numero_fatura` (número), `valor`, `vencimento` e `link`/`link_fatura`. Se o template tiver botão de URL com variável, o sufixo vem preenchido com o token do link público, e o template pode usar `https://admin.devbatista.com/f/{{1}}`. Se o cabeçalho for de documento, o PDF da fatura vai anexado sozinho. Marca `sent_at`.
- **Link público.** `/f/<token>`, sem login e sem prazo de validade (token assinado). Mostra o status, os itens, o total, o vencimento, o Pix e um botão para baixar o PDF. Se a fatura foi paga ou cancelada, a página mostra isso no lugar do Pix.
- **PDF.** Gerado na hora (Prawn, mesma identidade visual da proposta), na tela da fatura e no link público.

## Avisos

O aviso de atraso continua sendo o da rotina diária ("Pagamentos vencidos"). Para receitas que estão numa fatura emitida, sai **um aviso por fatura** ("Fatura FAT-2026-0001 vencida"), em vez de um por receita.

## Depois da fatura

Com a fatura paga, o botão **Registrar nota fiscal** abre Notas fiscais com o cliente, as receitas, a competência e o valor já preenchidos.

## Fora da v1

Lembretes ao cliente (e-mail ou WhatsApp) antes e depois do vencimento, gateway com boleto ou Pix dinâmico e baixa automática, pagamento parcial, geração automática de rascunhos, faturas na Visão 360º do cliente e na busca, e tools no MCP.
