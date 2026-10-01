# Personas e perfis de acesso

[← Índice](README.md)

O sistema é só para uso interno e tem cinco perfis; cada usuário tem exatamente um. O menu mostra apenas os módulos que o perfil pode ver, e toda permissão é checada no servidor (cap. 33 e 38).

| Perfil | Quem é | Pergunta que traz ao sistema | Tela de entrada |
| --- | --- | --- | --- |
| Administrador | Sócio ou gestor da DevBatista | Como está a empresa este mês e onde está o risco? | Dashboard executivo |
| Comercial | Quem atende leads e negocia | O que preciso fazer avançar no funil hoje? | Pipeline |
| Financeiro | Quem cobra, paga e concilia | O que vence, o que atrasou, quanto entrou? | Dashboard financeiro |
| Suporte | Quem atende chamados | Quais chamados são meus e quais são críticos? | Suporte |
| Desenvolvedor | Quem executa projetos e mantém a infraestrutura | Quais tarefas são minhas e o que está em produção? | Tarefas |

**Matriz de permissões inicial** (ajustável em Administração → Permissões)

| Módulo | Admin | Comercial | Financeiro | Suporte | Dev |
| --- | --- | --- | --- | --- | --- |
| Dashboard | Total | Leitura | Leitura | Leitura | Leitura |
| Comercial | Total | Edição | Leitura | — | — |
| Clientes e contatos | Total | Edição | Leitura | Leitura | Leitura |
| Contratos e serviços contratados | Total | Edição | Edição | Leitura | — |
| Projetos e tarefas | Total | Leitura | — | Leitura | Edição |
| Horas trabalhadas | Total | — | Leitura | Próprio | Próprio |
| Suporte | Total | Leitura | — | Edição | Edição |
| Financeiro | Total | — | Edição | — | — |
| Tecnologia | Total | — | Leitura | Leitura | Edição |
| Produtos | Total | Leitura | Leitura | — | Leitura |
| Fornecedores | Total | — | Edição | — | Leitura |
| Documentos | Total | Edição | Edição | Leitura | Leitura |
| Relatórios e indicadores | Total | Leitura | Leitura | Leitura | Leitura |
| Administração | Total | — | — | — | — |

Total = cria, edita, exclui e configura. Edição = cria e edita. Leitura = só consulta. Próprio = cria e edita só os próprios registros. No Dashboard e nos relatórios, cartões financeiros aparecem apenas para Administrador e Financeiro.
