# Requisitos não funcionais

[← Índice](README.md)

O MVP é uma aplicação web responsiva: desenhada para desktop, utilizável no celular desde a V1, e preparada para o aplicativo mobile da V2 sem reescrever regras de negócio.

| Tema | Requisito |
| --- | --- |
| Plataforma | Web, desktop primeiro (1280 px ou mais). Funcional a partir de 360 px: menu lateral vira gaveta, tabelas viram cartões, quadros kanban rolam na horizontal. |
| Preparo para mobile (V2) | Regras de negócio em models e services, nunca em views. Rotas JSON versionadas (/api/v1) para as telas que o app vai usar: Dashboard, Visão 360º, Chamados, Tarefas, Horas e Notificações. |
| Arquitetura | Monólito Rails modular, código organizado por domínio (Core, Comercial, Clientes, Operação, Financeiro, Tecnologia, Gestão, Administração). Sem microsserviços no MVP. |
| Stack | Ruby 3.3, Rails 8.1, PostgreSQL, Redis, Sidekiq + sidekiq-cron, Active Storage com AWS S3, Docker, deploy com Kamal. |
| Bibliotecas | Hotwire (Turbo + Stimulus) com o CSS de `docs/design/assets/app.css`, sem Tailwind; Devise (login, bloqueio, redefinição, expiração); Pundit (autorização); RSpec (testes). Auditoria em model próprio (AuditLog). Valores monetários guardados em centavos, como inteiro. |
| Jobs | Sidekiq roda: geração de recorrências, virada de status por vencimento (títulos, contratos, propostas, domínios), alertas e e-mails. Jobs idempotentes: rodar duas vezes no mesmo dia não duplica título nem alerta. |
| Autenticação e sessão | bcrypt, bloqueio após tentativas inválidas, link de redefinição de uso único, cookies Secure + HttpOnly + SameSite, expiração por inatividade. |
| Autorização | Checada no servidor em toda ação, não só escondendo botões. Busca global, relatórios e exportações respeitam o perfil. |
| Transporte | Somente HTTPS, com redirecionamento forçado e HSTS; proteção CSRF nativa do Rails ativa. |
| Credenciais de clientes | Nenhuma senha, chave ou token é armazenado; só a referência ao cofre de senhas. Se um dia for preciso, criptografia por campo. |
| Auditoria | Trilha imutável de criação, alteração, exclusão, mudança de status, login e movimentações financeiras, com valor anterior e novo. |
| Backup | Backup diário automatizado do banco, com retenção definida e teste periódico de restauração. |
| Logs | Acessos e erros registrados, sem dados sensíveis. |
| Integração futura com HubSpot | Company, Contact, Lead e Opportunity têm o campo external_id desde a V1, para a sincronização da V1.1. |
| Idioma e formato | Interface em português; código e entidades em inglês, no singular (convenção Rails). Moeda R$, datas dd/mm/aaaa, fuso America/Sao_Paulo. |
| Acessibilidade | Contraste AA, navegação por teclado em listagens e formulários, foco visível. |
| Desempenho | Meta proposta: listagens e Visão 360º abrem em menos de 1 s com 5 anos de dados; os indicadores do dashboard podem usar cache de até 15 min. Ainda não validada. |
