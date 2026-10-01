# Escopo

[← Índice](README.md)

A V1 entrega seis blocos e todos são compromisso. Automação, Portal do Cliente, app mobile e IA ficam para V1.1, V2 e V3.

**Dentro da V1**

| Bloco | Itens |
| --- | --- |
| Core | Autenticação, usuários e permissões, dashboard, clientes, contatos, busca global, auditoria |
| Comercial | Leads, pipeline, oportunidades, propostas |
| Operação | Catálogo e serviços contratados, contratos, projetos, tarefas, horas, chamados |
| Financeiro | Receitas, despesas, contas a receber e a pagar, recorrências, notas fiscais (registro) |
| Tecnologia | Aplicações, servidores, domínios, bancos de dados, integrações, serviços externos |
| Gestão | Fornecedores, documentos, produtos próprios, relatórios básicos, rentabilidade (custos diretos), indicadores, notificações |

**Sequência de construção.** A ordem segue as dependências do modelo de dados:

1. Core: usuários, perfis, empresas e contatos.
2. Comercial: leads, pipeline, oportunidades e propostas.
3. Operação: serviços contratados e contratos, depois projetos, tarefas, horas e chamados.
4. Financeiro: depende dos serviços contratados para gerar recorrências.
5. Tecnologia: inventário e custos por cliente.
6. Gestão: consolida custos, rentabilidade, relatórios e indicadores.

**Fora do MVP**

| Funcionalidade | Versão indicativa |
| --- | --- |
| Sincronização com HubSpot | V1.1 |
| Emissão automática de NF | V1.1 |
| Cobrança automática | V1.1 |
| WhatsApp integrado | V1.1 |
| Portal do cliente | V2 |
| Aplicativo mobile | V2 |
| Assinatura digital | V2 |
| Monitoramento automático de servidores | V2 |
| Gestão automática de DNS | V2 |
| Conciliação bancária | V2 |
| Integração contábil | V2 |
| Custo de mão de obra na rentabilidade | A definir |
| IA aplicada a propostas, suporte e rentabilidade | V3 |
| BI avançado | V3 |
