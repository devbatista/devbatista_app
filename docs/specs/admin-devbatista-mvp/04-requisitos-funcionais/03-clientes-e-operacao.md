# Requisitos funcionais — Clientes e Operação

[← Requisitos funcionais](README.md) · [Índice geral](../README.md)

12. **Empresas.** Como comercial, quero cadastrar a empresa com razão social, nome fantasia e CNPJ.
    - CNPJ validado (dígitos verificadores) e único no cadastro.
    - Status: Prospect, Ativo, Inativo. Listagens usam o nome fantasia.
13. **Contatos.** Como comercial, quero cadastrar vários contatos por empresa e marcar um como principal.
    - Só um contato principal por empresa; marcar outro desmarca o anterior.
    - O principal é sugerido por padrão em propostas, chamados e cobranças.
14. **Visão 360º.** Como qualquer perfil, quero ver em uma tela tudo o que a DevBatista mantém para um cliente. É a tela de maior prioridade do produto.
    - Cabeçalho: nome, status, "cliente desde" e 4 cartões (MRR, Projetos ativos, Chamados abertos, Próxima cobrança).
    - Nove abas: Resumo, Serviços, Contratos, Projetos, Chamados, Infraestrutura, Financeiro, Documentos, Atividades.
    - Cada aba respeita a permissão do perfil; uma aba sem acesso não aparece.
15. **Catálogo de serviços.** Como administrador, quero cadastrar o que a DevBatista vende, com categoria, tipo e preço padrão.
    - Tipo: Recorrente, Projeto ou Avulso. Serviço Inativo não aparece em novas propostas.
16. **Serviços contratados.** Como comercial ou financeiro, quero ligar um cliente a um serviço com valor, recorrência e dia de vencimento.
    - MRR do serviço: mensal = valor; trimestral ÷ 3; semestral ÷ 6; anual ÷ 12; avulso não entra.
    - Status: Ativo, Suspenso, Encerrado. Só serviços Ativos compõem o MRR.
17. **Contratos.** Como comercial, quero registrar o contrato com vigência, renovação, valor e o arquivo assinado.
    - Número interno sequencial gerado pelo sistema.
    - O status muda sozinho para Próximo do vencimento, com alertas a 60, 30 e 15 dias do término.
    - O arquivo assinado fica no módulo Documentos.
18. **Projetos.** Como desenvolvedor, quero acompanhar projetos por cliente com previsão, orçamento e progresso.
    - Atrasado = previsão ultrapassada e status diferente de Concluído ou Cancelado; aparece em destaque e gera alerta.
    - Progresso informado à mão ou calculado pelas tarefas concluídas.
19. **Tarefas.** Como desenvolvedor, quero ver as tarefas em lista ou em quadro por status.
    - Status: Backlog, A fazer, Em andamento, Em revisão, Concluída. Prioridade: Baixa, Normal, Alta, Urgente.
    - A tela mostra estimativa × horas registradas.
20. **Horas trabalhadas.** Como desenvolvedor ou suporte, quero registrar horas por cliente, com projeto e tarefa opcionais.
    - Cliente e duração são obrigatórios; perfis com permissão Próprio só editam os próprios lançamentos.
21. **Chamados.** Como suporte, quero abrir e acompanhar chamados com histórico de mensagens.
    - Número sequencial e data de abertura automáticos; data de conclusão registrada ao Resolver.
    - Fluxo: Aberto → Em análise → Em atendimento → Aguardando cliente → Resolvido → Fechado.
    - Categoria: erro, dúvida, melhoria, infraestrutura, acesso. Prioridade Crítica notifica na hora.
    - No MVP só a equipe abre chamados; o cliente abre pelo Portal na V2.
