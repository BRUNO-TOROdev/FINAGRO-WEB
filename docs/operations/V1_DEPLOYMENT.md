# FINAGRO Web V1 — deploy do piloto

## Pré-requisitos

- Projeto Supabase exclusivo para staging/piloto, com PostgreSQL 17.
- Projeto Vercel conectado ao repositório e domínio/subdomínio controlado.
- SMTP transacional com remetente institucional validado.
- Observabilidade aprovada (recomendado: Sentry) com redaction.
- Responsável nominal por deploy, banco, backup e incidentes.

Credenciais reais nunca entram no Git, em `.env*`, issues ou logs.

## Variáveis da aplicação

| Variável | Exemplo | Escopo |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://project-ref.supabase.co` | navegador e servidor |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | chave publicável | navegador e servidor |
| `NEXT_PUBLIC_SITE_URL` | `https://app.exemplo.com` | URL canônica do Auth |

O build de produção falha se alguma estiver ausente. Service role, senha do banco, token da CLI, SMTP e token de observabilidade são segredos exclusivos dos provedores/CI e nunca recebem prefixo `NEXT_PUBLIC_`.

## Supabase e migrations

1. Crie staging/piloto e registre o Project Ref fora do Git.
2. Confirme PostgreSQL 17 e backup anterior a cada mudança.
3. Autentique a CLI com segurança e execute `supabase link --project-ref <ref>`.
4. Confira `supabase migration list --linked`.
5. Aplique somente com `supabase db push --linked`. Nunca use `db reset` remoto.
6. Confirme as 22 migrations, de `202609020001` a `202610080022`, e faça verificações não destrutivas de RLS, grants e funções.
7. Não execute seed, dados demo ou testes destrutivos no remoto.

Mudança de schema exige nova migration forward-only. É proibido corrigir schema manualmente no painel.

## Auth e SMTP

- Site URL deve ser exatamente `NEXT_PUBLIC_SITE_URL`.
- Permita `https://<dominio>/auth/callback` e somente as URLs exatas de staging necessárias.
- Desabilite signup público no remoto; usuários são controlados pela administração.
- Exija ao menos 8 caracteres e mantenha refresh token rotation.
- Configure SMTP com TLS, remetente verificado e segredo somente no Supabase.
- Teste recuperação, expiração e retorno a `/redefinir-senha`.

## Vercel

1. Importe como Next.js; use `pnpm install --frozen-lockfile` e `pnpm build`.
2. Cadastre as três variáveis por ambiente. Staging e produção usam projetos e URLs distintos.
3. Proteja previews; não aponte preview público para dados de produção.
4. Publique primeiro em staging, valide `/api/health` e o smoke test.
5. Associe domínio após Auth, SMTP, backup e observabilidade estarem aprovados.

## Smoke test remoto

Use organização e usuários sintéticos, sem dados reais:

- login, logout, recuperação, membership ausente e READ_ONLY;
- isolamento cross-tenant com UUID direto;
- Fazenda, Safra, 154 contas e regra GENERAL vigente;
- PENDENTE/AGENDADO, baixa integral, reversão e parcelamento;
- financiamento, orçamento e publicação;
- DRE, DRE Safra, DFC, Projetado × Realizado e Dashboard;
- importação somente dry-run/staging;
- cenário reconciliado de lançamentos → allocations → relatórios.

Registre PASS/FAIL sem payload financeiro, documentos, dados bancários ou PII.

## Piloto e data de corte

Após o smoke test, crie organização, proprietário, memberships, Fazendas, Safras, plano FINAGRO (154 contas), contas bancárias, produtores/titulares e regra GENERAL confirmada para sua vigência. Não presuma 45/15/40. A data de corte é decisão humana; carregue apenas saldos iniciais, abertos, financiamentos ativos, orçamento vigente e configurações. As 16 linhas bloqueadas permanecem no staging.

## Rollback

- Aplicação: promova novamente o deployment anterior da Vercel.
- Banco: migrations são forward-only; não reverta schema manualmente e nunca restaure sobre produção.
- Falha de migration: interrompa novas escritas quando necessário, preserve diagnóstico e crie migration corretiva.
- Corrupção: acione o runbook e valide restore em ambiente isolado antes de qualquer ação em produção.
