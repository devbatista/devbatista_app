# Visão geral

[← Índice](README.md)

O Admin DevBatista é o backoffice interno que reúne em um só sistema o comercial, os clientes, a operação, o financeiro e a tecnologia da DevBatista. O MVP está cumprido quando a gestão responder às perguntas abaixo usando apenas o sistema, sem planilhas nem painéis de terceiros.

**Problemas que o MVP resolve**

- Dados de clientes, contratos, cobranças e infraestrutura espalhados em planilhas, e-mails e painéis de fornecedores.
- MRR, vencimentos e inadimplência calculados à mão.
- Custos de infraestrutura pagos em nome de clientes sem vínculo com a receita.
- Contratos, domínios e propostas que vencem sem aviso.
- Margem por cliente desconhecida.

**Critério de sucesso: perguntas que o sistema precisa responder**

| Tema | Pergunta | Onde o sistema responde |
| --- | --- | --- |
| Financeiro | Quanto a empresa fatura? Qual o MRR? Quanto há a receber? | Dashboard executivo e Dashboard financeiro |
| Financeiro | Quais clientes estão inadimplentes? | Contas a receber, filtro Vencido |
| Clientes | Quanto cada cliente paga e que serviços possui? | Visão 360º, aba Serviços |
| Clientes | Quais contratos estão vencendo? | Contratos, status Próximo do vencimento |
| Rentabilidade | Quanto custa manter cada cliente e qual a margem? | Rentabilidade por cliente |
| Rentabilidade | Quantas horas são usadas por cliente? | Relatório de horas |
| Operação | Quais projetos estão atrasados? | Dashboard e Projetos, filtro Atrasado |
| Operação | Quais oportunidades estão abertas? | Pipeline comercial |
| Tecnologia | Quais aplicações estão em produção e onde estão hospedadas? | Aplicações, filtro Produção |
| Tecnologia | Quais domínios estão vencendo? | Domínios, ordenado por vencimento |

**Princípio de projeto:** modelo de dados bem relacionado e base de código simples (monólito Rails modular), para que V1.1, V2 e V3 cresçam sem reescrita.
