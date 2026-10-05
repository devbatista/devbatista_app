# Dúvidas em aberto e premissas

[← Índice](README.md)

Foram encontradas dez lacunas ou contradições no documento original. As quatro que mudavam o escopo ou o modelo de dados foram decididas em 01/10/2026.

**Decididas**

- [x] **Escopo da V1.** Todas as 32 capacidades do cap. 2 entram na V1, incluindo horas, notas fiscais, bancos de dados, produtos, rentabilidade e indicadores.
- [x] **Lead × Oportunidade no pipeline.** O lead percorre Novo Lead → Qualificado. Na conversão nasce a oportunidade, e de Reunião em diante é ela que anda no kanban.
- [x] **Receita × título a receber** (e despesa × conta a pagar). Uma entidade só para cada lado: Receivable e Payable, com status Previsto, Pendente, Pago, Vencido e Cancelado. Receitas e Contas a receber são duas visões do mesmo registro.
- [x] **Entidades que faltavam.** Entram ProposalItem (itens da proposta), Subscription (assinaturas dos produtos), Role (perfil com matriz de permissões configurável) e Setting (listas e prazos configuráveis).

**Detalhar durante o desenvolvimento**

- [ ] **Horizonte das recorrências.** Quantos períodos à frente a rotina gera? Proposta: 3 meses, como no exemplo do cap. 18.
- [x] **Proposta Visualizada.** Premissa adotada na fase 3 (confirmar): marcação manual pelo botão "Cliente visualizou".
- [ ] **Câmbio.** De onde vem a cotação para converter despesas em dólar: digitada pelo financeiro ou de uma API?
- [x] **Probabilidade da oportunidade.** Premissa adotada na fase 3 (confirmar): sugerida pela etapa (Reunião 25%, Proposta 50%, Negociação 75%, Fechado 100%) e editável; ao mudar de etapa volta para a sugerida, a menos que seja alterada junto.
- [x] **Operação: alertas e estimativas.** Premissas adotadas na fase 4 (confirmar): projeto e tarefa atrasados avisam no primeiro dia de atraso e repetem o aviso a cada 7 dias; a estimativa do projeto é a soma das estimativas das tarefas; quem lança horas no nível Próprio pode excluir o próprio lançamento (como no envio de documentos).
- [ ] **Tentativas de login.** Quantas tentativas antes do bloqueio e por quanto tempo? Proposta: 5 tentativas, 15 minutos.
- [ ] **Churn e CAC.** Precisam de período padrão e regra para cliente que volta.

**Premissas adotadas**

- Uma única empresa (DevBatista), sem multi-tenant.
- Todos os valores na interface estão em reais; só serviços externos e despesas guardam moeda original.
- Os valores das telas do documento original são ilustrativos e servem como dados de exemplo para o design.
