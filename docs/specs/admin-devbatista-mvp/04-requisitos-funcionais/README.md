# Requisitos funcionais

[← Índice](../README.md)

São 42 histórias em seis áreas, na ordem de construção sugerida (Core → Comercial → Clientes e Operação → Financeiro → Tecnologia → Gestão). Cada história traz os critérios que o QA usa para aceitar a entrega. Campos, tipos e listas de status de cada entidade estão no documento original e não são repetidos aqui.

| Área | Histórias |
| --- | --- |
| [Core](01-core.md) | 1–5 |
| [Comercial](02-comercial.md) | 6–11 |
| [Clientes e Operação](03-clientes-e-operacao.md) | 12–21 |
| [Financeiro](04-financeiro.md) | 22–28 |
| [Tecnologia](05-tecnologia.md) | 29–34 |
| [Gestão e Administração](06-gestao-e-administracao.md) | 35–42 |

## Padrões comuns a todas as telas

- Toda listagem tem filtros, ordenação, paginação e o botão "Novo" (cap. 3).
- Todo registro ligado a um cliente tem um link de um clique para a Visão 360º daquele cliente.
- Toda criação, alteração, exclusão e mudança de status gera um evento em Activity e em AuditLog.
- Campos do tipo Seleção usam as listas fechadas do documento original; motivos de perda e prazos de alerta são configuráveis em Administração → Configurações.
- Valores em reais (R$), datas em dd/mm/aaaa e fuso America/Sao_Paulo.
