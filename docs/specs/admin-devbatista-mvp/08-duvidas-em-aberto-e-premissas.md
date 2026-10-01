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
- [ ] **Proposta Visualizada.** Como o sistema sabe que o cliente abriu a proposta, se não há portal na V1? Proposta: marcação manual no MVP.
- [ ] **Câmbio.** De onde vem a cotação para converter despesas em dólar: digitada pelo financeiro ou de uma API?
- [ ] **Probabilidade da oportunidade.** Livre ou sugerida pela etapa do pipeline?
- [ ] **Tentativas de login.** Quantas tentativas antes do bloqueio e por quanto tempo? Proposta: 5 tentativas, 15 minutos.
- [ ] **Churn e CAC.** Precisam de período padrão e regra para cliente que volta.

**Premissas adotadas**

- Uma única empresa (DevBatista), sem multi-tenant.
- Todos os valores na interface estão em reais; só serviços externos e despesas guardam moeda original.
- Os valores das telas do documento original são ilustrativos e servem como dados de exemplo para o design.
