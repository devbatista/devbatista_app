# Requisitos funcionais — Gestão e Administração

[← Requisitos funcionais](README.md) · [Índice geral](../README.md)

35. **Produtos próprios.** Como administrador, quero acompanhar CatalystOps, PrescSign e outros produtos com status, MRR, clientes e custo mensal.
    - Submenu com Produtos próprios, Assinaturas (registro manual no MVP) e Indicadores por produto.
36. **Fornecedores.** Como financeiro, quero cadastrar fornecedores com as mesmas categorias das despesas.
37. **Documentos.** Como qualquer perfil com edição, quero anexar arquivos e ligá-los a cliente, projeto, contrato, proposta ou fornecedor.
    - Upload por Active Storage em S3; "enviado por" e data automáticos.
38. **Relatórios.** Como gestor, quero 19 relatórios básicos em 4 áreas (Financeiro, Comercial, Clientes, Operação).
    - Todos com filtro por período e exportação CSV; os financeiros também filtram por cliente e serviço.
39. **Rentabilidade por cliente.** Como administrador, quero saber quanto cada cliente deixa de margem no mês.
    - Margem antes da mão de obra = receita mensal − custos diretos (serviços externos pagos pela DevBatista, servidores, domínios e despesas com centro de custo no cliente).
    - Mostra o valor e o percentual sobre a receita, com a lista de custos que compõem o total.
    - Custo de mão de obra (horas × custo/hora) fica para depois do MVP.
40. **Indicadores.** Como administrador, quero 14 indicadores calculados, nenhum digitado: MRR, ARR, Faturamento, Margem, Ticket médio, Clientes ativos, Receita por cliente, Receita por serviço, CAC, Churn, Horas por cliente, Custo de infraestrutura, Propostas abertas e Taxa de conversão.
41. **Auditoria.** Como administrador, quero consultar a trilha de auditoria filtrando por usuário, módulo, tipo de evento e período.
    - Cada registro guarda usuário, data e hora, registro afetado, valor anterior e novo.
    - Nenhum perfil edita ou exclui um registro de auditoria.
42. **Configurações.** Como administrador, quero ajustar listas e prazos sem deploy: motivos de perda, antecedência dos alertas e matriz de permissões.
