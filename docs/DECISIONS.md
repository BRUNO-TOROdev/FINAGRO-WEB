# FINAGRO Web — Decisões da Fundação de Dados v0.2

## Núcleo operacional financeiro — 2026-09-03

- Contrapartes, contas bancárias e lançamentos reutilizam as entidades homologadas; nenhuma entidade paralela foi criada.
- `save_financial_entry` é a única operação pública usada pela interface para criar/editar lançamento e sua apropriação. A função executa lançamento e apropriações na mesma transação e valida novamente permissões e referências no PostgreSQL.
- A edição de um lançamento `PAGO` ou com liquidação ativa é bloqueada nesta etapa. Alterações de valor, fazenda ou regra regeneram apropriações atomicamente; alterações em outros campos preservam o snapshot já gravado.
- Apropriação direta cria uma única linha de 100%. Rateio usa exclusivamente regra ativa da mesma organização e safra, criando várias apropriações sem multiplicar o lançamento ou o pagamento.
- O centavo residual continua seguindo o motor homologado: é atribuído à última fazenda na ordenação determinística por UUID, garantindo soma exata do valor.
- Vendedor/beneficiado é representado pela contraparte opcional existente. Não foi criado um segundo vínculo complexo nesta etapa.
- Forma de pagamento permanece separada da conta bancária. Parcelamentos e liquidações continuam fora do escopo visual.
- A listagem usa RPC paginada, com limite máximo de 100 linhas por chamada (25 na interface), e aplica filtros no PostgreSQL sob RLS.
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

## Plano de Contas e Regras de Rateio v0.1 — 2026-09-03

- A migration `202609030007_chart_accounts_allocation_configuration.sql` adiciona
  nível materializado e proteção contra ciclos à árvore de `chart_accounts`. O
  banco recalcula níveis descendentes quando uma conta é reposicionada.
- Templates são copiados explicitamente e uma única vez por organização/template.
  A cópia registra origem e versão, mas passa a ser integralmente tenant-owned.
- O catálogo FINAGRO completo não foi populado: não existe dataset homologado no
  repositório. A pendência e o contrato mínimo estão em
  `docs/data/FINAGRO_CHART_TEMPLATE_PENDING.md`.
- `allocation_rules.is_active=false` representa RASCUNHO e `true` representa ATIVA.
  A RPC `save_allocation_rule` salva cabeçalho e itens em uma transação, valida
  safra/fazendas no tenant e exige soma `NUMERIC` exatamente igual a 100 para ativar.
- A interface calcula percentuais em milionésimos inteiros (`BigInt`), nunca com
  ponto flutuante; a validação definitiva permanece no PostgreSQL.

## Template Oficial do Plano de Contas FINAGRO V1 — 2026-09-03

- A única fonte é `FINAGRO - Planilha Financeira (Em branco).xlsx`, aba
  `Plano de Contas`. O binário permanece local e ignorado pelo Git; SHA-256,
  células e relações extraídas ficam no arquivo canônico e no relatório.
- A lista `Plano_de_Contas` alimenta o campo Grupo da Base de Dados; o Subgrupo
  é resolvido por `INDIRECT($D7)`. Foram homologados 27 Grupos e 127 Subgrupos.
- `display_name` substitui somente underscore por espaço. `source_name`, célula
  de origem, nível, pai e aliases permanecem rastreáveis no template e na cópia.
- As colisões pai/filho de Entrada de Financiamento e Saldo Inicial de Caixa são
  intencionais e diferenciadas por ID, nível e pai, não por alteração do nome.
- `Desp_com_Pessoal_*` é o valor operacional comprovado. `Despesa_com_Pessoal_*`
  aparece somente como cabeçalho das listas de Subgrupos e é mantido como alias.
- Os códigos `FINAGRO-V1-*` são identificadores internos estáveis, não códigos
  contábeis. Como a fonte não fornece os campos gerenciais do novo schema, o
  template usa `OUTRO`/`NEUTRA` e flags financeiras desativadas, sem inferência.
