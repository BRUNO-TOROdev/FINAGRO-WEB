# FINAGRO DB Foundation v0.2

Pacote de fundação PostgreSQL/Supabase elaborado a partir do PRD FINAGRO e da engenharia reversa das planilhas.

## Conteúdo

```text
supabase/migrations/
  202609020001_core.sql
  202609020002_security_rls.sql
  202609020003_business_invariants.sql
  202609020004_reporting_views.sql

tests/
  TEST_PLAN.md
  business_invariants_smoke.sql

docs/
  DECISIONS.md

CODEX_PROMPT_ETAPA_BANCO.md
```

## Ordem de aplicação
1. Core schema.
2. Security/RLS e catálogo de permissões.
3. Invariantes, motor de rateio, liquidações e auditoria.
4. Views de relatório.

## Requisitos técnicos
- PostgreSQL/Supabase.
- Supabase Auth (`auth.users`, `auth.uid()`, `auth.role()`).
- Ambiente local de desenvolvimento antes de qualquer produção.

## Regra de execução
Não aplicar diretamente em produção. Primeiro:
1. criar projeto local;
2. aplicar migrations em banco descartável;
3. automatizar os testes P0;
4. corrigir qualquer falha;
5. somente então conectar a primeira interface.

## O que este pacote já protege
- isolamento por organização;
- FKs compostas cross-tenant;
- status restritos;
- `PAGO` vinculado a liquidação integral;
- rateio ativo = 100%;
- snapshot de rateio;
- rateio por Safra e rateio Geral da organização com vigência;
- apropriação = valor exato do lançamento;
- dinheiro sem float;
- liquidação imutável/reversível;
- trilha de auditoria;
- views com RLS preservada.

## O que ainda não é considerado produção-ready
Este é um release candidate arquitetural validado em Supabase local. Antes de
produção ainda são necessários revisão independente, gestão de secrets,
observabilidade, estratégia de backup/restore e validação de carga.

## Execução local validada

Pré-requisitos: Docker Desktop, Supabase CLI e Python 3.12+.

```powershell
supabase start
supabase db reset --local

python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r tests\requirements.txt
.\.venv\Scripts\python.exe tests\run_sql_tests.py
```

Resultado esperado:

```text
PASS business_invariants_smoke.sql
PASS p0_foundation.sql
```

Os testes são transacionais e terminam com `ROLLBACK`. A suíte P0 cria dois
usuários em `auth.users`, duas organizações e executa as verificações RLS como
role `authenticated`; a conexão `postgres` é usada somente para preparar os
fixtures e controlar a transação de teste.

No ambiente Windows validado, `supabase/config.toml` mantém Edge Runtime e
Analytics desabilitados porque não fazem parte desta etapa de banco. Isso evita
dependência do health check de Edge Functions e da exposição insegura do daemon
Docker em `tcp://localhost:2375`.
