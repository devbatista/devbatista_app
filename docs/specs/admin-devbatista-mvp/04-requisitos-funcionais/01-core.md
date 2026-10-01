# Requisitos funcionais — Core

[← Requisitos funcionais](README.md) · [Índice geral](../README.md)

1. **Login.** Como usuário, quero entrar com e-mail e senha para acessar só o que meu perfil permite.
   - Senha guardada com bcrypt; a conta é bloqueada após tentativas inválidas seguidas.
   - Redefinição de senha por link de uso único com expiração curta.
   - Sessão expira por inatividade; login e falhas de login entram na auditoria.
2. **Usuários.** Como administrador, quero criar, editar e desativar usuários e definir o perfil de cada um.
   - Usuário desativado não entra, mas continua nos registros históricos.
   - O menu e as ações seguem a matriz de permissões; chamar uma rota sem permissão retorna 403.
3. **Dashboard executivo.** Como administrador, quero ver os 12 cartões do mês corrente para entender a empresa em um minuto.
   - Cartões: Faturamento, Receita recebida, Receita prevista, Despesas, Resultado, MRR, Clientes ativos, Contratos ativos, Projetos ativos, Chamados abertos, Contas vencidas, Propostas abertas.
   - Cada cartão usa a definição do cap. 4 e leva à listagem já filtrada.
   - Seletor de período; o padrão é o mês corrente.
   - Seis gráficos dos últimos seis meses: Receitas, Despesas, Resultado, Evolução do MRR, Receita por serviço, Receita por cliente.
   - Feed de Atividades recentes com hora, descrição e módulo.
   - Perfis sem acesso ao financeiro não veem cartões nem gráficos financeiros.
4. **Busca global.** Como usuário, quero buscar qualquer registro pela barra superior, com atalho de teclado (⌘K / Ctrl+K).
   - Pesquisa em clientes, contatos, projetos, propostas, contratos, chamados, faturas e aplicações.
   - Resultados agrupados por tipo, apenas do que o perfil pode ver.
5. **Notificações.** Como usuário, quero uma central de notificações com os alertas do meu perfil.
   - Uma rotina diária (Sidekiq) gera os 7 alertas do cap. 36; e-mail é opcional por usuário.
   - Chamado Crítico notifica na hora, sem esperar a rotina diária.
   - Notificação tem estado lida/não lida e um link para o registro.
