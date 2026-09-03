# FINAGRO Web — Decisões da Fundação de Dados v0.2

## Status
Somente `PENDENTE`, `AGENDADO`, `PAGO`.

`PAGO` não é um campo livre: a base exige liquidação integral. Reversão de baixa retira o status `PAGO`.

## Rateio por safra
- A classificação histórica `GERAL` não é uma fazenda.
- Despesas compartilhadas usam `allocation_rules` vinculadas a `crop_seasons`.
- Regra ativa precisa somar 100%.
- Regra começa inativa para permitir edição antes da ativação.
- Aplicação gera `entry_allocations` como snapshot histórico.
- Alterar percentuais da regra modifica apenas aplicações futuras.
- Alterar a safra de uma regra já utilizada é bloqueado.
- Mais de uma fazenda no mesmo lançamento exige regra formal de rateio.

## Arredondamento
Valores monetários são `NUMERIC(18,2)`. Percentuais são `NUMERIC(9,6)`.

Ao aplicar rateio, cada linha é arredondada a centavos e eventual resíduo fica na última fazenda da ordenação determinística. A soma das apropriações deve ser exatamente igual ao valor do lançamento.

## Plano de contas
- `chart_accounts` pertence à organização.
- Hierarquia via `parent_id`, sem limite rígido Grupo/Subgrupo.
- FINAGRO será disponibilizado como template copiável; o cliente edita sua cópia.
- Conta inativa não pode ser usada em novo lançamento.
- Conta com `requires_crop_season=true` exige Safra.
- Registro histórico não é recalculado quando a conta é posteriormente renomeada/inativada.

## Multi-tenancy
- `organization_id` é a fronteira do tenant.
- FKs compostas impedem relacionar IDs de organizações diferentes.
- RLS é aplicada nas tabelas tenant-owned.
- Helpers `private.is_org_member()` e `private.has_permission()` são `SECURITY DEFINER`, com `search_path` vazio.
- Views de relatório são `security_invoker` para respeitar RLS das tabelas-base.

## Perfis padrão
- Proprietário
- Administrador
- Financeiro
- Operacional
- Somente leitura

Perfis são apenas defaults. Permissões ficam normalizadas e podem ser ajustadas posteriormente.

## Lançamentos e parcelas
- `installment_plans` não tem efeito financeiro.
- Cada parcela real é um `financial_entry`.
- Isso elimina dupla contagem do pai + parcelas.

## Liquidações
- `settlements` pode modelar múltiplas liquidações, embora o MVP possa expor baixa total inicialmente.
- Soma ativa nunca pode superar o valor do lançamento.
- Liquidação é imutável; correção = reversão + nova liquidação.
- Reversão exige justificativa e usuário.

## Datas
- DRE: `issue_date`.
- Fluxo previsto: `due_date`.
- Fluxo realizado/extrato bancário futuro: `settlements.settled_at`.

## Auditoria
Triggers registram alterações relevantes em `audit_logs`, incluindo mudança de status, soft delete e reversão de liquidação.

## Pontos conscientemente deixados para a próxima camada
1. Seed integral do plano de contas FINAGRO a partir da planilha analisada.
2. Serviço de geração de parcelamento que force soma das parcelas = total do plano.
3. Invariante equivalente de 100% para apropriações de orçamento.
4. Regra especial completa da DRE Safra, após validação dos casos históricos anômalos.
5. Dataset anonimizado de regressão contra a planilha preenchida.

## Validação local e hardening v0.2.1 — 2026-09-03

As migrations foram executadas do zero no Supabase CLI 2.116.0, com PostgreSQL
17.6. O ambiente local de banco desabilita Edge Runtime e Analytics porque esta
etapa não possui Edge Functions e o health check do Edge Runtime retornou HTTP
500 no Docker Desktop para Windows. Auth, API, PostgREST, Storage e PostgreSQL
continuam ativos.

Correções técnicas comprovadas durante execução:

1. Funções internas no schema `private` não herdam mais `EXECUTE` de `PUBLIC`.
   `authenticated` executa apenas `private.is_org_member()` e
   `private.has_permission()`, necessárias às policies RLS.
2. Reversão direta por `UPDATE settlements` foi removida. A única interface para
   usuários autenticados é `public.reverse_settlement()`, que valida permissão,
   exige motivo e grava `auth.uid()`.
3. `settlements.created_by` é preenchido pelo banco e não pode ser forjado por
   usuário autenticado.
4. A RPC de reversão não revela a existência de UUIDs de outros tenants:
   liquidação ausente e liquidação sem autorização retornam o mesmo erro.
5. Dois triggers genéricos acessavam campos inexistentes do record `OLD/NEW`
   quando disparados por tabelas de outro formato. Auditoria passou a ler o JSON
   genérico, e o trigger de apropriação separa a ramificação por tabela.
6. Parcelas vinculadas agora têm número único por plano. Ao completar as `N`
   parcelas ativas, a soma `NUMERIC` deve ser exatamente igual ao total do plano;
   o plano continua sem impacto financeiro próprio.

A suíte `tests/p0_foundation.sql` usa IDs fixos de teste, transação com `ROLLBACK`
e alterna para o role PostgreSQL `authenticated` com claims de dois usuários
reais em `auth.users`. RLS nunca é desabilitada.

## Fundação da aplicação v0.1 — 2026-09-03

- A migration `202609030006_app_foundation.sql` é aditiva e não modifica as cinco
  migrations financeiras homologadas.
- A URL do tenant usa um `organizations.slug` imutável no banco, gerado pelo
  banco com sufixo do UUID para evitar colisões. O slug é apenas navegação: sessão,
  membership ativa, role e permissões continuam sendo resolvidos no servidor.
- E-mails permanecem em `auth.users`. A aplicação os consulta somente pela RPC
  `list_organization_members`, que é `SECURITY DEFINER`, tem `search_path` vazio e
  exige `users.manage` no tenant solicitado.
- Trocas de perfil passam pela RPC `change_membership_role`. Ela bloqueia mudança
  do próprio perfil, acesso cross-tenant e atribuição/alteração de Proprietário por
  quem não seja Proprietário.
- Convites externos ficaram fora desta etapa porque ainda não há decisão sobre
  provedor de e-mail, expiração, reenvio e aceite. A tela administra memberships
  existentes e documenta essa pendência.
