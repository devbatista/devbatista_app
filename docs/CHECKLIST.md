# Checklist de desenvolvimento — Admin DevBatista (MVP)

Acompanha a construção da V1, fase por fase. Cada item é um requisito funcional (RF) das [specs](specs/admin-devbatista-mvp/04-requisitos-funcionais/README.md), com link para a regra e para a tela do [design](design/index.html). Os subitens são os critérios de aceite: cada um vira pelo menos um teste.

Marque `[x]` só quando o item cumprir o [Pronto quando](#pronto-quando) abaixo.

**Andamento:** fases 1 a 6 concluídas · próxima: fase 7 (Gestão e dashboard)

## Pronto quando

Vale para todo módulo antes de marcar como concluído:

- [ ] Testes (RSpec) cobrindo os critérios de aceite e as regras de integridade do [modelo de dados](specs/admin-devbatista-mvp/06-modelo-de-dados.md)
- [ ] Permissão checada no servidor (`authorize` + policy com a área certa); perfil sem acesso recebe 403
- [ ] Criação, alteração, exclusão e mudança de status geram `AuditLog` (`include Auditable`) e `Activity`
- [ ] Listagem com filtros, ordenação, paginação e botão "Novo"
- [ ] Registro ligado a cliente tem link de um clique para a Visão 360º
- [ ] Item do menu ligado à rota em `NavigationHelper::NAV` (sai de "em breve")
- [ ] Seeds com os mesmos dados do design, coerentes com as outras telas
- [ ] Tela conferida contra o design no desktop e no celular (360 px)
- [ ] `bin/rubocop` e `bin/brakeman` sem apontamentos
- [ ] Spec atualizada se alguma regra mudou durante o desenvolvimento

---

## Fase 1 · Base ✅

- [x] App Rails 8.1, PostgreSQL, Redis, Sidekiq + sidekiq-cron, Hotwire, RSpec
- [x] Docker para desenvolvimento (app na 3847, banco na 5847)
- [x] Layout com o design system, menu filtrado pelo perfil, trilha de navegação
- [x] E-mail: letter_opener_web local, Amazon SES em produção; arquivos no S3 em produção
- [x] **RF 1 · Login** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/01-core.md) · [login](design/acesso/login.html) · [recuperar senha](design/acesso/recuperar-senha.html)
  - [x] Senha com bcrypt; conta bloqueada após tentativas inválidas seguidas
  - [x] Redefinição por link de uso único com expiração curta (2 h)
  - [x] Sessão expira por inatividade (30 min)
  - [x] Login e falhas de login na auditoria
  - [ ] Confirmar a regra de bloqueio adotada: 5 tentativas, 15 minutos ([dúvida](specs/admin-devbatista-mvp/08-duvidas-em-aberto-e-premissas.md))
- [x] **RF 2 · Usuários** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/01-core.md) · [usuários](design/administracao/usuarios.html)
  - [x] Criar, editar e desativar; um perfil por usuário
  - [x] Usuário desativado não entra e continua nos registros históricos
  - [x] Menu e ações seguem a matriz de permissões; rota sem permissão responde 403
- [x] **RF 41 · Auditoria** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/06-gestao-e-administracao.md) · [logs](design/administracao/logs.html)
  - [x] Filtros por usuário, módulo, tipo de evento e período
  - [x] Guarda usuário, data e hora, registro afetado, valor anterior e novo
  - [x] Nenhum perfil edita ou exclui (model somente leitura + trigger no banco)
- [x] **RF 42 · Configurações (parte 1): matriz de permissões** — [permissões](design/administracao/permissoes.html)

## Fase 2 · Clientes ✅

Primeiro módulo de negócio. Traz também o que os outros módulos vão usar: histórico de atividades, documentos, notificações, configurações e busca.

- [x] **Activity** — histórico de negócio, polimórfico (registro + usuário + descrição), usado no feed do dashboard e na aba Atividades
- [x] **RF 42 · Configurações (parte 2)** — [configurações](design/administracao/configuracoes.html)
  - [x] Model `Setting` com listas e prazos editáveis sem deploy
  - [x] Antecedência dos alertas (contratos 60/30/15, domínios 60/30/7)
- [x] **RF 12 · Empresas** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/03-clientes-e-operacao.md) · [empresas](design/clientes/empresas.html)
  - [x] CNPJ validado (dígitos verificadores) e único
  - [x] Status: Prospect, Ativo, Inativo; listagens usam o nome fantasia
  - [x] Campo `external_id` para o HubSpot
- [x] **RF 13 · Contatos** — [contatos](design/clientes/contatos.html)
  - [x] Vários por empresa; só um principal (marcar outro desmarca o anterior)
  - [x] Principal sugerido por padrão em propostas, chamados e cobranças
  - [x] Campo `external_id` para o HubSpot
- [x] **RF 15 · Catálogo de serviços** — [catálogo](design/administracao/catalogo-servicos.html)
  - [x] Categoria, tipo (Recorrente, Projeto, Avulso) e preço padrão
  - [x] Serviço Inativo não aparece em novos serviços contratados
  - [x] Nem em novas propostas
- [x] **RF 16 · Serviços contratados** — [serviços contratados](design/clientes/servicos-contratados.html)
  - [x] MRR calculado, nunca digitado: mensal = valor; trimestral ÷ 3; semestral ÷ 6; anual ÷ 12; avulso fora
  - [x] Status Ativo, Suspenso, Encerrado; só Ativo compõe o MRR
- [x] **RF 17 · Contratos** — [contratos](design/clientes/contratos.html) · [contrato](design/clientes/contrato.html)
  - [x] Número interno sequencial gerado pelo sistema
  - [x] Status vira Próximo do vencimento sozinho (job diário), com alertas a 60, 30 e 15 dias
  - [x] Arquivo assinado guardado em Documentos
- [x] **RF 37 · Documentos** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/06-gestao-e-administracao.md) · [documentos](design/gestao/documentos.html)
  - [x] Upload por Active Storage (S3 em produção)
  - [x] Vínculo polimórfico e obrigatório; nesta fase, cliente ou contrato
  - [x] Proposta, projeto e fornecedor
  - [x] "Enviado por" e data automáticos
- [x] **RF 5 · Notificações (base)** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/01-core.md) · [central](design/geral/notificacoes.html)
  - [x] Central com lida/não lida e link para o registro; sino da barra superior
  - [x] Rotina diária (Sidekiq) que gera os alertas; cada fase acrescenta os seus
  - [x] E-mail opcional por usuário, por tipo de alerta (central de notificações → Preferências)
  - [x] Primeiro alerta: contratos vencendo (Comercial e Administrador)
- [x] **RF 4 · Busca global (base)** — [resultados](design/geral/busca.html)
  - [x] Barra superior e atalho ⌘K / Ctrl+K
  - [x] Resultados agrupados por tipo, só do que o perfil pode ver
  - [x] Nesta fase: clientes, contatos e contratos (cada fase acrescenta os seus tipos)
- [x] **RF 14 · Visão 360º (parte 1)** — [empresa](design/clientes/empresa.html)
  - [x] Cabeçalho: nome, status, "cliente desde" e 4 cartões (MRR, Projetos ativos, Chamados abertos, Próxima cobrança)
  - [x] Abas desta fase: Resumo, Serviços, Contratos, Documentos, Atividades
  - [x] Aba sem permissão não aparece

## Fase 3 · Comercial ✅

- [x] **RF 6 · Leads** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/02-comercial.md) · [leads](design/comercial/leads.html) · [lead](design/comercial/lead.html)
  - [x] Origem obrigatória (WhatsApp, Indicação, Site, Diagnóstico, Meta Ads, Google Ads, LinkedIn, Outbound, Outros)
  - [x] Data de entrada automática; campo `external_id`
- [x] **RF 7 · Pipeline** — [pipeline](design/comercial/pipeline.html)
  - [x] Kanban com 7 etapas; arrastar muda a etapa
  - [x] Lead até Qualificado; de Reunião em diante o cartão é a oportunidade
  - [x] Perdido em qualquer etapa aberta, com motivo obrigatório
  - [x] Cada coluna mostra quantidade e valor somado
- [x] **RF 8 · Converter lead** — [lead](design/comercial/lead.html)
  - [x] Gera empresa, contato e oportunidade sem redigitar
  - [x] Avisa se já existe empresa com o mesmo CNPJ
- [x] **RF 9 · Oportunidades** — [oportunidades](design/comercial/oportunidades.html)
  - [x] Valor estimado, probabilidade, previsão de fechamento; campo `external_id`
  - [x] Previsão ponderada = valor × probabilidade, no pipeline e nas oportunidades (relatórios na fase 7)
- [x] **RF 10 · Propostas** — [propostas](design/comercial/propostas.html) · [proposta](design/comercial/proposta.html)
  - [x] Itens do catálogo (ProposalItem); total = soma dos itens; preço padrão editável
  - [x] Status: Rascunho, Enviada, Visualizada, Aprovada, Recusada, Expirada
  - [x] Enviada ou Visualizada vira Expirada ao fim da validade; responsável avisado 3 dias antes
- [x] **RF 11 · Fechar negócio** — [proposta](design/comercial/proposta.html)
  - [x] Proposta aprovada gera contrato e serviços contratados com cliente, valores e prazos dela
  - [x] Empresa passa a Ativo
- [x] **RF 42 · Configurações (parte 3):** motivos de perda editáveis
- [x] Busca global: propostas e leads
- [x] Visão 360º: cartão Comercial com oportunidades e propostas em aberto
- [x] Interações registradas no lead e na oportunidade (ligação, WhatsApp, e-mail, reunião, nota)
- [x] Contato principal sugerido ao criar proposta
- [x] Documentos: vínculo com proposta
- [x] Notificações: propostas expirando (responsável pela proposta)
- [x] Probabilidade sugerida pela etapa e editável (premissa adotada; [confirmar](specs/admin-devbatista-mvp/08-duvidas-em-aberto-e-premissas.md))
- [x] Proposta Visualizada por marcação manual (premissa adotada; confirmar)

## Fase 4 · Operação ✅

- [x] **RF 18 · Projetos** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/03-clientes-e-operacao.md) · [projetos](design/operacao/projetos.html) · [projeto](design/operacao/projeto.html)
  - [x] Atrasado = previsão ultrapassada e status diferente de Concluído ou Cancelado; destaque e alerta
  - [x] Progresso manual ou calculado pelas tarefas concluídas
- [x] **RF 19 · Tarefas** — [tarefas](design/operacao/tarefas.html)
  - [x] Lista e quadro; status Backlog, A fazer, Em andamento, Em revisão, Concluída
  - [x] Prioridade Baixa, Normal, Alta, Urgente
  - [x] Estimativa × horas registradas
- [x] **RF 20 · Horas trabalhadas** — [horas](design/operacao/horas.html)
  - [x] Cliente e duração obrigatórios; projeto e tarefa opcionais
  - [x] Perfil "Próprio" só edita os próprios lançamentos
- [x] **RF 21 · Chamados** — [chamados](design/operacao/chamados.html) · [chamado](design/operacao/chamado.html)
  - [x] Número sequencial e data de abertura automáticos; data de conclusão ao Resolver
  - [x] Fluxo Aberto → Em análise → Em atendimento → Aguardando cliente → Resolvido → Fechado
  - [x] Categorias: erro, dúvida, melhoria, infraestrutura, acesso
  - [x] Histórico de mensagens (TicketMessage)
  - [x] Prioridade Crítica notifica na hora, sem esperar a rotina diária
- [x] Visão 360º: abas Projetos e Chamados
- [x] Busca global: projetos e chamados
- [x] Contato principal sugerido ao abrir chamado
- [x] Documentos: vínculo com projeto
- [x] Notificações: tarefas e projetos atrasados (aviso no 1º dia e a cada 7), chamado crítico na hora
- [x] Visão 360º: cartões Projetos ativos e Chamados abertos
- [x] Premissas adotadas (estimativa do projeto = soma das tarefas; lembrete a cada 7 dias de atraso; [confirmar](specs/admin-devbatista-mvp/08-duvidas-em-aberto-e-premissas.md))

## Fase 5 · Financeiro ✅

- [x] **RF 36 · Fornecedores** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/06-gestao-e-administracao.md) · [fornecedores](design/gestao/fornecedores.html)
  - [x] Mesmas categorias das despesas
- [x] **RF 23 · Receitas** e **RF 25 · Contas a receber** (um só model, `Receivable`) — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/04-financeiro.md) · [receitas](design/financeiro/receitas.html) · [contas a receber](design/financeiro/contas-receber.html)
  - [x] Receitas lista por competência; Contas a receber, por vencimento
  - [x] Status Previsto, Pendente, Pago, Vencido, Cancelado
  - [x] Vira Vencido no dia seguinte ao vencimento sem pagamento; atraso em dias; alerta
  - [x] Filtro "Vencido" = inadimplentes
  - [x] Categoria sugerida pelo serviço do catálogo
- [x] **RF 24 · Despesas** e **RF 26 · Contas a pagar** (um só model, `Payable`) — [despesas](design/financeiro/despesas.html) · [contas a pagar](design/financeiro/contas-pagar.html)
  - [x] Fornecedor, categoria e centro de custo (área interna ou cliente)
  - [x] Despesa com cliente entra no custo direto dele
  - [x] Moeda estrangeira: valor original, moeda e valor em R$ na data do pagamento
  - [x] Ligação com fornecedor e cliente
  - [x] Ligação com serviço externo (fase 6)
- [x] **RF 27 · Recorrências** — [recorrências](design/financeiro/recorrencias.html)
  - [x] Job gera títulos dos próximos períodos a partir dos serviços contratados ativos, como Previsto (diário às 06:00 e "Executar rotina agora")
  - [x] Idempotente: rodar duas vezes no mesmo dia não duplica título
  - [x] Mudar o valor do serviço altera só títulos futuros não pagos
  - [x] Encerrar o serviço cancela os títulos posteriores
  - [x] Despesas recorrentes seguem a mesma regra
- [x] **RF 28 · Notas fiscais** — [notas fiscais](design/financeiro/notas-fiscais.html)
  - [x] Número, competência, valor e PDF, XML ou link
  - [x] Status Pendente de emissão, Emitida, Cancelada
- [x] **RF 22 · Dashboard financeiro** — [financeiro](design/financeiro/financeiro.html)
  - [x] 7 cartões do mês: Faturamento, Recebido, A receber, Vencido, Despesas, Resultado, MRR
  - [x] Teste de consistência: Faturamento = Recebido + A receber + Vencido
- [x] Visão 360º: aba Financeiro e cartão Próxima cobrança
- [x] Busca global: faturas
- [x] Contato principal sugerido nas cobranças
- [x] Documentos: vínculo com fornecedor
- [x] Notificações: pagamentos vencidos (receber) e contas a pagar vencidas, para Financeiro e Administrador
- [x] Visão 360º: Próxima cobrança calculada pelos títulos (sem títulos, estima pelos serviços contratados)
- [x] Decidido: horizonte das recorrências de 3 meses além do mês corrente (editável em Configurações)
- [x] Decidido: câmbio pela PTAX de venda do Banco Central (API Olinda), com cotações guardadas, última conhecida como fallback e correção manual no pagamento
- [x] RF 42 · Configurações (parte 4): categorias de despesa, centros de custo internos e horizonte das recorrências

## Fase 6 · Tecnologia e Produtos ✅

- [x] **RF 29 · Aplicações** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/05-tecnologia.md) · [aplicações](design/tecnologia/aplicacoes.html) · [aplicação](design/tecnologia/aplicacao.html)
  - [x] Hospedagem aponta para servidor ou serviço externo; status Ativa, Em manutenção, Desativada
- [x] **RF 30 · Servidores** — [servidores](design/tecnologia/servidores.html)
- [x] **RF 31 · Domínios** — [domínios](design/tecnologia/dominios.html)
  - [x] Alertas a 60, 30 e 7 dias do vencimento
  - [x] Destaque para domínio sem renovação automática
- [x] **RF 32 · Bancos de dados** — [bancos de dados](design/tecnologia/bancos-dados.html)
- [x] **RF 33 · Integrações** — [integrações](design/tecnologia/integracoes.html)
- [x] **RF 34 · Serviços externos** — [serviços externos](design/tecnologia/servicos-externos.html)
  - [x] Custo, moeda, periodicidade e quem paga (DevBatista ou Cliente)
  - [x] Só os pagos pela DevBatista entram no custo direto do cliente
  - [x] Contas a pagar e despesas recorrentes ligadas ao serviço externo
- [x] Nenhum model de Tecnologia tem campo de senha, chave ou token; só referência ao cofre (teste que verifica as colunas e validação que recusa credencial colada no texto)
- [x] **RF 35 · Produtos próprios** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/06-gestao-e-administracao.md) · [produtos](design/produtos/produtos.html) · [assinaturas](design/produtos/assinaturas.html) · [indicadores](design/produtos/produtos-indicadores.html)
  - [x] Status, MRR, clientes e custo mensal
  - [x] Assinaturas (Subscription) com registro manual
- [x] Visão 360º: aba Infraestrutura
- [x] Busca global: aplicações
- [x] Notificações: domínios vencendo (prazos já configuráveis) e domínio vencido sem renovação
- [x] Chamado com aplicação afetada; detalhe da aplicação com mapa de dependências, custo mensal e chamados
- [x] Visão 360º: custo mensal de infraestrutura pago pela DevBatista (base da rentabilidade da fase 7)
- [x] Premissas adotadas (model App no lugar de Application; inadimplentes contam no MRR dos produtos; [confirmar](specs/admin-devbatista-mvp/08-duvidas-em-aberto-e-premissas.md))

## Fase 7 · Gestão e dashboard

- [x] **RF 3 · Dashboard executivo** — [spec](specs/admin-devbatista-mvp/04-requisitos-funcionais/01-core.md) · [dashboard](design/dashboard/dashboard.html)
  - [x] 12 cartões do mês, cada um levando à listagem já filtrada
  - [x] Seletor de período (padrão: mês corrente)
  - [x] 6 gráficos dos últimos 6 meses
  - [x] Feed de atividades recentes
  - [x] Cartões e gráficos financeiros só para Administrador e Financeiro
  - [x] Cache de até 15 min nos indicadores
- [x] **RF 38 · Relatórios** — [relatórios](design/gestao/relatorios.html)
  - [x] 19 relatórios em 4 áreas, com filtro por período e exportação CSV
  - [x] Financeiros também filtram por cliente e serviço
  - [x] Respeitam o perfil
- [x] **RF 39 · Rentabilidade por cliente** — [rentabilidade](design/gestao/rentabilidade.html)
  - [x] Margem = receita mensal − custos diretos (serviços externos pagos pela DevBatista, servidores, domínios, despesas com centro de custo no cliente)
  - [x] Valor, percentual e lista dos custos que compõem o total
- [x] **RF 40 · Indicadores** — [indicadores](design/gestao/indicadores.html)
  - [x] Os 14 calculados, nenhum digitado
- [x] Decidir: período padrão e regra de cliente que volta para Churn e CAC

## Fase 8 · API e produção

- [ ] **API `/api/v1`** em JSON para o app mobile da V2: Dashboard, Visão 360º, Chamados, Tarefas, Horas e Notificações, com a mesma autorização das telas
- [x] Hospedagem no Railway
- [ ] **Arquivos no S3**
  - [ ] Bucket `devbatista-admin-production` em `sa-east-1`, com acesso público bloqueado
  - [ ] Usuário IAM só para o app, com permissão de listar, ler, gravar e apagar nesse bucket
  - [ ] `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` e `AWS_BUCKET` no `devbatista_app` e no `sidekiq` (Railway)
  - [ ] Teste de upload e download de um documento em produção
- [x] **E-mail pelo SES**: credenciais no `devbatista_app` e no `sidekiq`
- [x] Domínio com HTTPS e HSTS
- [ ] Backup diário do banco, com retenção definida e teste de restauração
- [ ] Logs de acesso e erro sem dados sensíveis
- [ ] CI no GitHub (testes, rubocop e brakeman a cada push)
- [ ] Meta de desempenho validada: listagens e Visão 360º abaixo de 1 s com 5 anos de dados
- [x] Primeiro administrador criado em produção (`SEED_PASSWORD`)
