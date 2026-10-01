# Requisitos funcionais — Financeiro

[← Requisitos funcionais](README.md) · [Índice geral](../README.md)

22. **Dashboard financeiro.** Como financeiro, quero 7 cartões do mês: Faturamento, Recebido, A receber, Vencido, Despesas, Resultado e MRR.
    - Faturamento = Recebido + A receber + Vencido (regra de consistência testada).
23. **Receitas.** Como financeiro, quero registrar receitas por competência, vencimento e pagamento.
    - Receita e título a receber são o mesmo registro (Receivable): esta tela lista por competência, Contas a receber lista por vencimento.
    - Status: Previsto, Pendente, Pago, Vencido, Cancelado. Categoria sugerida a partir do serviço do catálogo.
24. **Despesas.** Como financeiro, quero registrar despesas por fornecedor, categoria e centro de custo.
    - Despesa e conta a pagar são o mesmo registro (Payable), com os mesmos status das receitas.
    - Centro de custo pode ser uma área interna ou um cliente; despesa com cliente entra no custo direto dele.
    - Despesa em moeda estrangeira guarda valor original, moeda e valor em reais na data do pagamento.
25. **Contas a receber.** Como financeiro, quero ver todos os títulos a receber com vencidos em destaque.
    - Colunas: vencimento, cliente, serviço, contrato, valor, atraso, status.
    - No dia seguinte ao vencimento sem pagamento o status vira Vencido, o atraso em dias é calculado e o alerta é disparado.
    - Filtro "Vencido" = lista de inadimplentes.
26. **Contas a pagar.** Como financeiro, quero o mesmo controle para fornecedores, ligando cada título a fornecedor, serviço externo e cliente quando houver.
27. **Recorrências.** Como financeiro, quero que os títulos dos próximos períodos sejam gerados sozinhos a partir dos serviços contratados ativos.
    - Respeita valor, periodicidade e dia de vencimento; títulos nascem como Previsto.
    - Mudar o valor do serviço altera só títulos futuros não pagos.
    - Encerrar o serviço cancela os títulos posteriores à data de encerramento.
    - Despesas recorrentes seguem a mesma regra em contas a pagar.
28. **Notas fiscais.** Como financeiro, quero registrar as notas emitidas fora do sistema, com número, competência, valor e PDF, XML ou link.
    - Status: Pendente de emissão, Emitida, Cancelada. Emissão automática fica para a V1.1.
