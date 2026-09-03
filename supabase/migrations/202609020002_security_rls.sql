-- FINAGRO Web — Security, Roles and RLS v0.2

create schema if not exists private;
revoke all on schema private from public;

-- =========================================================
-- PERMISSION CATALOG
-- =========================================================

insert into public.permissions (code, description) values
('org.manage', 'Administrar dados da organização'),
('users.manage', 'Administrar usuários, perfis e permissões'),
('farms.view', 'Visualizar fazendas'),
('farms.manage', 'Criar e editar fazendas'),
('seasons.view', 'Visualizar safras'),
('seasons.manage', 'Criar e editar safras'),
('chart_accounts.view', 'Visualizar plano de contas'),
('chart_accounts.manage', 'Criar, editar e inativar contas'),
('allocation_rules.view', 'Visualizar regras de rateio'),
('allocation_rules.manage', 'Criar, editar e ativar regras de rateio'),
('parties.view', 'Visualizar contrapartes'),
('parties.manage', 'Criar e editar contrapartes'),
('bank_accounts.view', 'Visualizar contas bancárias'),
('bank_accounts.manage', 'Criar e editar contas bancárias'),
('payment_methods.view', 'Visualizar formas de pagamento'),
('payment_methods.manage', 'Criar e editar formas de pagamento'),
('entries.view', 'Visualizar lançamentos financeiros'),
('entries.create', 'Criar lançamentos financeiros'),
('entries.update', 'Editar lançamentos não pagos'),
('entries.delete', 'Excluir logicamente lançamentos não pagos'),
('entries.manage_paid', 'Alterar lançamento já pago'),
('settlements.create', 'Registrar baixas e recebimentos'),
('settlements.reverse', 'Reverter baixas e recebimentos'),
('financing.view', 'Visualizar financiamentos'),
('financing.manage', 'Criar e editar financiamentos'),
('budgets.view', 'Visualizar orçamento e projeções'),
('budgets.manage', 'Criar e editar orçamento e projeções'),
('reports.view', 'Visualizar DRE, DFC, dashboards e relatórios'),
('imports.execute', 'Executar importações em lote'),
('audit.view', 'Visualizar trilha de auditoria')
on conflict (code) do update set description = excluded.description;

-- =========================================================
-- RLS HELPER FUNCTIONS
-- =========================================================

create or replace function private.is_org_member(target_org uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        auth.role() = 'service_role'
        or exists (
            select 1
            from public.memberships m
            where m.organization_id = target_org
              and m.user_id = auth.uid()
              and m.is_active = true
        );
$$;

create or replace function private.has_permission(target_org uuid, permission_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        auth.role() = 'service_role'
        or exists (
            select 1
            from public.memberships m
            join public.roles r
              on r.id = m.role_id
             and r.organization_id = m.organization_id
            join public.role_permissions rp
              on rp.role_id = r.id
             and rp.organization_id = r.organization_id
            join public.permissions p
              on p.id = rp.permission_id
            where m.organization_id = target_org
              and m.user_id = auth.uid()
              and m.is_active = true
              and p.code = permission_code
        );
$$;

revoke all on function private.is_org_member(uuid) from public;
revoke all on function private.has_permission(uuid, text) from public;
grant usage on schema private to authenticated;
grant execute on function private.is_org_member(uuid) to authenticated;
grant execute on function private.has_permission(uuid, text) to authenticated;

-- =========================================================
-- DEFAULT ROLE SEEDER
-- =========================================================

create or replace function private.seed_default_roles(target_org uuid, owner_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    owner_role uuid;
    admin_role uuid;
    finance_role uuid;
    ops_role uuid;
    read_role uuid;
begin
    insert into public.roles (organization_id, name, is_system_role)
    values (target_org, 'Proprietário', true)
    returning id into owner_role;

    insert into public.roles (organization_id, name, is_system_role)
    values (target_org, 'Administrador', true)
    returning id into admin_role;

    insert into public.roles (organization_id, name, is_system_role)
    values (target_org, 'Financeiro', true)
    returning id into finance_role;

    insert into public.roles (organization_id, name, is_system_role)
    values (target_org, 'Operacional', true)
    returning id into ops_role;

    insert into public.roles (organization_id, name, is_system_role)
    values (target_org, 'Somente leitura', true)
    returning id into read_role;

    -- Proprietário and Administrador: all current permissions.
    insert into public.role_permissions (organization_id, role_id, permission_id)
    select target_org, owner_role, p.id from public.permissions p;

    insert into public.role_permissions (organization_id, role_id, permission_id)
    select target_org, admin_role, p.id from public.permissions p;

    -- Financeiro: full financial operation, reports and financial master data,
    -- without organization/user administration.
    insert into public.role_permissions (organization_id, role_id, permission_id)
    select target_org, finance_role, p.id
    from public.permissions p
    where p.code = any (array[
        'farms.view','seasons.view','chart_accounts.view','chart_accounts.manage',
        'allocation_rules.view','allocation_rules.manage','parties.view','parties.manage',
        'bank_accounts.view','bank_accounts.manage','payment_methods.view','payment_methods.manage',
        'entries.view','entries.create','entries.update','entries.delete','entries.manage_paid',
        'settlements.create','settlements.reverse','financing.view','financing.manage',
        'budgets.view','budgets.manage','reports.view','imports.execute','audit.view'
    ]::text[]);

    -- Operacional: can register and maintain non-paid entries, but cannot pay,
    -- change paid entries, alter financial structure or administer users.
    insert into public.role_permissions (organization_id, role_id, permission_id)
    select target_org, ops_role, p.id
    from public.permissions p
    where p.code = any (array[
        'farms.view','seasons.view','chart_accounts.view','allocation_rules.view',
        'parties.view','parties.manage','bank_accounts.view','payment_methods.view',
        'entries.view','entries.create','entries.update','reports.view'
    ]::text[]);

    -- Read-only role.
    insert into public.role_permissions (organization_id, role_id, permission_id)
    select target_org, read_role, p.id
    from public.permissions p
    where p.code = any (array[
        'farms.view','seasons.view','chart_accounts.view','allocation_rules.view',
        'parties.view','bank_accounts.view','payment_methods.view','entries.view',
        'financing.view','budgets.view','reports.view'
    ]::text[]);

    insert into public.memberships (organization_id, user_id, role_id)
    values (target_org, owner_user, owner_role);
end;
$$;

revoke all on function private.seed_default_roles(uuid, uuid) from public;

-- Bootstrap RPC for the first organization of an authenticated user.
create or replace function public.create_organization(
    p_legal_name text,
    p_trade_name text default null,
    p_tax_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    new_org uuid;
    caller uuid;
begin
    caller := auth.uid();
    if caller is null then
        raise exception 'AUTH_REQUIRED';
    end if;

    if p_legal_name is null or length(trim(p_legal_name)) = 0 then
        raise exception 'LEGAL_NAME_REQUIRED';
    end if;

    insert into public.organizations (legal_name, trade_name, tax_id)
    values (trim(p_legal_name), nullif(trim(p_trade_name), ''), nullif(trim(p_tax_id), ''))
    returning id into new_org;

    perform private.seed_default_roles(new_org, caller);
    return new_org;
end;
$$;

revoke all on function public.create_organization(text, text, text) from public;
grant execute on function public.create_organization(text, text, text) to authenticated;

-- =========================================================
-- ENABLE RLS
-- =========================================================

alter table public.organizations enable row level security;
alter table public.permissions enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.memberships enable row level security;
alter table public.farms enable row level security;
alter table public.crop_seasons enable row level security;
alter table public.chart_account_templates enable row level security;
alter table public.chart_account_template_items enable row level security;
alter table public.chart_accounts enable row level security;
alter table public.parties enable row level security;
alter table public.bank_accounts enable row level security;
alter table public.payment_methods enable row level security;
alter table public.allocation_rules enable row level security;
alter table public.allocation_rule_items enable row level security;
alter table public.installment_plans enable row level security;
alter table public.financial_entries enable row level security;
alter table public.entry_allocations enable row level security;
alter table public.settlements enable row level security;
alter table public.financing_contracts enable row level security;
alter table public.financing_installments enable row level security;
alter table public.budgets enable row level security;
alter table public.budget_items enable row level security;
alter table public.budget_item_allocations enable row level security;
alter table public.audit_logs enable row level security;

-- Global permission/template catalogs are readable by authenticated users.
create policy permissions_read on public.permissions
for select to authenticated
using (true);

create policy chart_templates_read on public.chart_account_templates
for select to authenticated
using (is_active = true);

create policy chart_template_items_read on public.chart_account_template_items
for select to authenticated
using (exists (
    select 1 from public.chart_account_templates t
    where t.id = template_id and t.is_active = true
));

-- Organization / membership administration.
create policy organizations_read on public.organizations
for select to authenticated
using (private.is_org_member(id));

create policy organizations_update on public.organizations
for update to authenticated
using (private.has_permission(id, 'org.manage'))
with check (private.has_permission(id, 'org.manage'));

create policy roles_read on public.roles
for select to authenticated
using (private.is_org_member(organization_id));

create policy roles_manage_insert on public.roles
for insert to authenticated
with check (private.has_permission(organization_id, 'users.manage'));

create policy roles_manage_update on public.roles
for update to authenticated
using (private.has_permission(organization_id, 'users.manage'))
with check (private.has_permission(organization_id, 'users.manage'));

create policy role_permissions_read on public.role_permissions
for select to authenticated
using (private.is_org_member(organization_id));

create policy role_permissions_manage_insert on public.role_permissions
for insert to authenticated
with check (private.has_permission(organization_id, 'users.manage'));

create policy role_permissions_manage_delete on public.role_permissions
for delete to authenticated
using (private.has_permission(organization_id, 'users.manage'));

create policy memberships_read on public.memberships
for select to authenticated
using (user_id = auth.uid() or private.has_permission(organization_id, 'users.manage'));

create policy memberships_manage_insert on public.memberships
for insert to authenticated
with check (private.has_permission(organization_id, 'users.manage'));

create policy memberships_manage_update on public.memberships
for update to authenticated
using (private.has_permission(organization_id, 'users.manage'))
with check (private.has_permission(organization_id, 'users.manage'));

-- =========================================================
-- DOMAIN POLICIES
-- =========================================================

-- Farms
create policy farms_read on public.farms for select to authenticated
using (private.has_permission(organization_id, 'farms.view'));
create policy farms_insert on public.farms for insert to authenticated
with check (private.has_permission(organization_id, 'farms.manage'));
create policy farms_update on public.farms for update to authenticated
using (private.has_permission(organization_id, 'farms.manage'))
with check (private.has_permission(organization_id, 'farms.manage'));

-- Crop seasons
create policy seasons_read on public.crop_seasons for select to authenticated
using (private.has_permission(organization_id, 'seasons.view'));
create policy seasons_insert on public.crop_seasons for insert to authenticated
with check (private.has_permission(organization_id, 'seasons.manage'));
create policy seasons_update on public.crop_seasons for update to authenticated
using (private.has_permission(organization_id, 'seasons.manage'))
with check (private.has_permission(organization_id, 'seasons.manage'));

-- Chart accounts
create policy chart_accounts_read on public.chart_accounts for select to authenticated
using (private.has_permission(organization_id, 'chart_accounts.view'));
create policy chart_accounts_insert on public.chart_accounts for insert to authenticated
with check (private.has_permission(organization_id, 'chart_accounts.manage'));
create policy chart_accounts_update on public.chart_accounts for update to authenticated
using (private.has_permission(organization_id, 'chart_accounts.manage'))
with check (private.has_permission(organization_id, 'chart_accounts.manage'));

-- Allocation rules and items
create policy allocation_rules_read on public.allocation_rules for select to authenticated
using (private.has_permission(organization_id, 'allocation_rules.view'));
create policy allocation_rules_insert on public.allocation_rules for insert to authenticated
with check (private.has_permission(organization_id, 'allocation_rules.manage'));
create policy allocation_rules_update on public.allocation_rules for update to authenticated
using (private.has_permission(organization_id, 'allocation_rules.manage'))
with check (private.has_permission(organization_id, 'allocation_rules.manage'));

create policy allocation_rule_items_read on public.allocation_rule_items for select to authenticated
using (private.has_permission(organization_id, 'allocation_rules.view'));
create policy allocation_rule_items_insert on public.allocation_rule_items for insert to authenticated
with check (private.has_permission(organization_id, 'allocation_rules.manage'));
create policy allocation_rule_items_update on public.allocation_rule_items for update to authenticated
using (private.has_permission(organization_id, 'allocation_rules.manage'))
with check (private.has_permission(organization_id, 'allocation_rules.manage'));
create policy allocation_rule_items_delete on public.allocation_rule_items for delete to authenticated
using (private.has_permission(organization_id, 'allocation_rules.manage'));

-- Parties
create policy parties_read on public.parties for select to authenticated
using (private.has_permission(organization_id, 'parties.view'));
create policy parties_insert on public.parties for insert to authenticated
with check (private.has_permission(organization_id, 'parties.manage'));
create policy parties_update on public.parties for update to authenticated
using (private.has_permission(organization_id, 'parties.manage'))
with check (private.has_permission(organization_id, 'parties.manage'));

-- Bank accounts
create policy bank_accounts_read on public.bank_accounts for select to authenticated
using (private.has_permission(organization_id, 'bank_accounts.view'));
create policy bank_accounts_insert on public.bank_accounts for insert to authenticated
with check (private.has_permission(organization_id, 'bank_accounts.manage'));
create policy bank_accounts_update on public.bank_accounts for update to authenticated
using (private.has_permission(organization_id, 'bank_accounts.manage'))
with check (private.has_permission(organization_id, 'bank_accounts.manage'));

-- Payment methods
create policy payment_methods_read on public.payment_methods for select to authenticated
using (private.has_permission(organization_id, 'payment_methods.view'));
create policy payment_methods_insert on public.payment_methods for insert to authenticated
with check (private.has_permission(organization_id, 'payment_methods.manage'));
create policy payment_methods_update on public.payment_methods for update to authenticated
using (private.has_permission(organization_id, 'payment_methods.manage'))
with check (private.has_permission(organization_id, 'payment_methods.manage'));

-- Installment plans
create policy installment_plans_read on public.installment_plans for select to authenticated
using (private.has_permission(organization_id, 'entries.view'));
create policy installment_plans_insert on public.installment_plans for insert to authenticated
with check (private.has_permission(organization_id, 'entries.create'));
create policy installment_plans_update on public.installment_plans for update to authenticated
using (private.has_permission(organization_id, 'entries.update'))
with check (private.has_permission(organization_id, 'entries.update'));

-- Financial entries
create policy entries_read on public.financial_entries for select to authenticated
using (private.has_permission(organization_id, 'entries.view'));

create policy entries_insert on public.financial_entries for insert to authenticated
with check (private.has_permission(organization_id, 'entries.create'));

create policy entries_update on public.financial_entries for update to authenticated
using (
    case
        when status = 'PAGO' then private.has_permission(organization_id, 'entries.manage_paid')
        else private.has_permission(organization_id, 'entries.update')
    end
)
with check (
    private.is_org_member(organization_id)
    and (
        status <> 'PAGO'
        or private.has_permission(organization_id, 'entries.manage_paid')
        or private.has_permission(organization_id, 'settlements.create')
    )
);

-- Allocations follow entry rights. No physical DELETE policy for financial entries.
create policy entry_allocations_read on public.entry_allocations for select to authenticated
using (private.has_permission(organization_id, 'entries.view'));
create policy entry_allocations_insert on public.entry_allocations for insert to authenticated
with check (private.has_permission(organization_id, 'entries.create') or private.has_permission(organization_id, 'entries.update'));
create policy entry_allocations_update on public.entry_allocations for update to authenticated
using (private.has_permission(organization_id, 'entries.update') or private.has_permission(organization_id, 'entries.manage_paid'))
with check (private.has_permission(organization_id, 'entries.update') or private.has_permission(organization_id, 'entries.manage_paid'));
create policy entry_allocations_delete on public.entry_allocations for delete to authenticated
using (private.has_permission(organization_id, 'entries.update') or private.has_permission(organization_id, 'entries.manage_paid'));

-- Settlements: immutable as rows; reversal is an UPDATE controlled separately.
create policy settlements_read on public.settlements for select to authenticated
using (private.has_permission(organization_id, 'entries.view'));
create policy settlements_insert on public.settlements for insert to authenticated
with check (private.has_permission(organization_id, 'settlements.create'));
create policy settlements_reverse_update on public.settlements for update to authenticated
using (private.has_permission(organization_id, 'settlements.reverse'))
with check (private.has_permission(organization_id, 'settlements.reverse'));

-- Financing
create policy financing_contracts_read on public.financing_contracts for select to authenticated
using (private.has_permission(organization_id, 'financing.view'));
create policy financing_contracts_insert on public.financing_contracts for insert to authenticated
with check (private.has_permission(organization_id, 'financing.manage'));
create policy financing_contracts_update on public.financing_contracts for update to authenticated
using (private.has_permission(organization_id, 'financing.manage'))
with check (private.has_permission(organization_id, 'financing.manage'));

create policy financing_installments_read on public.financing_installments for select to authenticated
using (private.has_permission(organization_id, 'financing.view'));
create policy financing_installments_insert on public.financing_installments for insert to authenticated
with check (private.has_permission(organization_id, 'financing.manage'));
create policy financing_installments_update on public.financing_installments for update to authenticated
using (private.has_permission(organization_id, 'financing.manage'))
with check (private.has_permission(organization_id, 'financing.manage'));

-- Budgets
create policy budgets_read on public.budgets for select to authenticated
using (private.has_permission(organization_id, 'budgets.view'));
create policy budgets_insert on public.budgets for insert to authenticated
with check (private.has_permission(organization_id, 'budgets.manage'));
create policy budgets_update on public.budgets for update to authenticated
using (private.has_permission(organization_id, 'budgets.manage'))
with check (private.has_permission(organization_id, 'budgets.manage'));

create policy budget_items_read on public.budget_items for select to authenticated
using (private.has_permission(organization_id, 'budgets.view'));
create policy budget_items_insert on public.budget_items for insert to authenticated
with check (private.has_permission(organization_id, 'budgets.manage'));
create policy budget_items_update on public.budget_items for update to authenticated
using (private.has_permission(organization_id, 'budgets.manage'))
with check (private.has_permission(organization_id, 'budgets.manage'));
create policy budget_items_delete on public.budget_items for delete to authenticated
using (private.has_permission(organization_id, 'budgets.manage'));

create policy budget_allocations_read on public.budget_item_allocations for select to authenticated
using (private.has_permission(organization_id, 'budgets.view'));
create policy budget_allocations_insert on public.budget_item_allocations for insert to authenticated
with check (private.has_permission(organization_id, 'budgets.manage'));
create policy budget_allocations_update on public.budget_item_allocations for update to authenticated
using (private.has_permission(organization_id, 'budgets.manage'))
with check (private.has_permission(organization_id, 'budgets.manage'));
create policy budget_allocations_delete on public.budget_item_allocations for delete to authenticated
using (private.has_permission(organization_id, 'budgets.manage'));

-- Audit is append-only to application users; trigger functions write it.
create policy audit_read on public.audit_logs for select to authenticated
using (private.has_permission(organization_id, 'audit.view'));
