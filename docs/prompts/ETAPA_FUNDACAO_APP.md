# Prompt Codex — FINAGRO Web / Fundação da Aplicação

Atue como engenheiro sênior Full Stack especializado em Next.js, TypeScript, Supabase, PostgreSQL, SaaS multi-tenant e segurança.

## Antes de começar
Leia integralmente:
- `AGENTS.md`;
- PRD funcional FINAGRO;
- arquitetura PostgreSQL;
- migrations Supabase;
- plano de testes de banco;
- `docs/APP_ARCHITECTURE.md`.

Se as migrations ainda não estiverem executando do zero com testes P0 verdes, NÃO avance para esta etapa.

## Objetivo
Construir somente a fundação da aplicação: autenticação, contexto de organização, shell protegido, perfis/permissões e primeiros cadastros simples. Não criar ainda lançamentos financeiros, DRE, fluxo de caixa ou dashboards reais.

## Entregas
1. Inicializar Next.js + TypeScript com configuração estrita.
2. Integrar Supabase SSR/Auth de forma server-first.
3. Implementar login e logout.
4. Implementar onboarding/criação de organização via RPC segura já definida no banco.
5. Implementar seleção de organização para usuários com múltiplos memberships.
6. Implementar rota/layout protegido por `organizationSlug`.
7. Criar helpers server-side:
   - `requireUser()`
   - `requireOrganizationMembership()`
   - `requirePermission()`
8. Criar shell executivo do app com navegação lateral/topbar.
9. Menu deve refletir permissões reais retornadas do banco.
10. Criar cadastro CRUD seguro de Fazendas.
11. Criar cadastro CRUD seguro de Safras.
12. Criar tela mínima de Usuários/Perfis para Proprietário/Administrador.
13. Criar página “Sem acesso” e tratamento consistente de 401/403/404.
14. Configurar Zod, lint, typecheck, Vitest e Playwright.
15. Criar testes E2E com Usuário A/Organização A e Usuário B/Organização B.
16. Provar que A não consegue navegar nem executar ações na organização B.

## Restrições
- Não usar service role no client.
- Não aceitar `organization_id` do formulário como prova de tenant.
- Resolver organização server-side a partir de slug + membership.
- Não colocar regras financeiras no frontend.
- Não criar mocks permanentes para permissões.
- Não hardcode fazendas/safras FINAGRO.
- Não implementar lançamentos financeiros nesta etapa.

## UX
Idioma pt-BR. Layout corporativo, limpo e sóbrio. Evitar aparência genérica de template SaaS. Priorizar leitura rápida e poucos cliques.

## Critério de conclusão
Execute e reporte:
- lint;
- typecheck;
- testes unitários;
- testes E2E;
- build de produção.

Tudo deve ficar verde.

Ao terminar, entregue resumo dos arquivos, decisões, testes e riscos. Pare e aguarde revisão antes de implementar Plano de Contas/Rateios.
