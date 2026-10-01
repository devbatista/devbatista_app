# Admin DevBatista

Sistema interno de gestão da DevBatista: comercial, clientes, operação, financeiro, tecnologia, produtos e gestão em um só lugar.

- **Specs:** [`docs/specs/admin-devbatista-mvp/`](docs/specs/admin-devbatista-mvp/README.md)
- **Design (protótipo de todas as telas):** [`docs/design/`](docs/design/README.md)
- **Design system:** [`docs/design/DESIGN-SYSTEM.md`](docs/design/DESIGN-SYSTEM.md)
- **Checklist de desenvolvimento:** [`docs/CHECKLIST.md`](docs/CHECKLIST.md)

## Stack

Ruby 3.3, Rails 8.1, PostgreSQL 17, Redis, Sidekiq + sidekiq-cron, Hotwire, Devise, Pundit, RSpec. Arquivos no S3 (Active Storage), e-mail pelo Amazon SES, deploy com Kamal. Detalhes e justificativas em [Requisitos não funcionais](docs/specs/admin-devbatista-mvp/05-requisitos-nao-funcionais.md).

## Rodando com Docker

```bash
docker compose up
```

| Serviço | Endereço |
| --- | --- |
| App | http://localhost:3847 |
| E-mails enviados (letter_opener) | http://localhost:3847/letter_opener |
| PostgreSQL | `localhost:5847`, usuário e senha `postgres` |

Na primeira vez, crie os perfis e a equipe de exemplo:

```bash
docker compose run --rm web bin/rails db:seed
```

Entre com `rafael@devbatista.com.br` e a senha `devbatista123`. Os outros usuários de exemplo (um por perfil) estão em [`db/seeds.rb`](db/seeds.rb).

Para mudar as portas: `APP_PORT=4000 DB_PORT_HOST=5500 docker compose up`.

### Comandos úteis

```bash
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec   # testes
docker compose run --rm web bin/rubocop                           # estilo
docker compose run --rm web bin/brakeman                          # segurança
docker compose run --rm web bin/rails console
docker compose logs -f sidekiq
```

## Rodando sem Docker

Com PostgreSQL e Redis locais:

```bash
bundle install
bin/rails db:prepare db:seed
bin/dev                      # app em http://localhost:3000
bundle exec sidekiq          # em outro terminal
```

## Organização

- **Permissões:** a matriz de cada perfil fica em `Role#permissions` (área → nível). Cada controller chama `authorize` e cada policy declara a área que protege (`app/policies`). Sem permissão, a rota responde 403.
- **Auditoria:** models com `include Auditable` registram criação, alteração, exclusão e mudança de status em `AuditLog`. Login, logout e falhas de login vêm dos hooks em `config/initializers/audit_hooks.rb`. A tabela é só de inserção, garantida por trigger no banco. Por isso o schema é `db/structure.sql`.
- **Visual:** `app/assets/stylesheets/app.css` é cópia de `docs/design/assets/app.css`. Mudança no design system entra nos dois. O que é só do app fica em `application.css`.
- **Interações:** `app/javascript/ui.js` implementa os atributos `data-open`, `data-tabs`, `data-filter` etc. do design system, compatíveis com o Turbo.
- **Rotinas diárias:** `config/schedule.yml` (sidekiq-cron).
- **Menu:** `NavigationHelper::NAV`. Item sem rota aparece como "em breve".

## Produção

O `Dockerfile` gera a imagem de produção, publicada com Kamal (`config/deploy.yml`). As variáveis de ambiente necessárias estão em [`.env.example`](.env.example): banco, Redis, S3, SES e o host público.
