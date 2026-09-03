-- FINAGRO Web — Core Schema v0.2
-- Target: PostgreSQL / Supabase

create extension if not exists pgcrypto;

-- =========================================================
-- GLOBAL / TENANCY
-- =========================================================

create table public.organizations (
    id uuid primary key default gen_random_uuid(),
    legal_name text not null,
    trade_name text,
    tax_id text,
    currency_code char(3) not null default 'BRL',
    timezone text not null default 'America/Sao_Paulo',
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.permissions (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    description text not null
);

create table public.roles (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    name text not null,
    is_system_role boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, name),
    unique (id, organization_id)
);

create table public.role_permissions (
    organization_id uuid not null references public.organizations(id),
    role_id uuid not null,
    permission_id uuid not null references public.permissions(id),
    primary key (role_id, permission_id),
    foreign key (role_id, organization_id)
        references public.roles(id, organization_id)
        on delete cascade
);

create table public.memberships (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    user_id uuid not null references auth.users(id) on delete cascade,
    role_id uuid not null,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, user_id),
    unique (id, organization_id),
    foreign key (role_id, organization_id)
        references public.roles(id, organization_id)
);

-- =========================================================
-- MASTER DATA
-- =========================================================

create table public.farms (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    name text not null,
    internal_code text,
    total_area_ha numeric(14,4),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, name),
    unique (id, organization_id),
    check (total_area_ha is null or total_area_ha >= 0)
);

create table public.crop_seasons (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    name text not null,
    season_type text not null check (season_type in ('PRINCIPAL','SAFRINHA','OUTRA')),
    crop_name text,
    starts_on date,
    ends_on date,
    is_closed boolean not null default false,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, name),
    unique (id, organization_id),
    check (starts_on is null or ends_on is null or ends_on >= starts_on)
);

-- Global reusable templates. These are copied into chart_accounts per organization.
create table public.chart_account_templates (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,
    version text not null,
    is_active boolean not null default true,
    created_at timestamptz not null default now()
);

create table public.chart_account_template_items (
    id uuid primary key default gen_random_uuid(),
    template_id uuid not null references public.chart_account_templates(id) on delete cascade,
    parent_item_id uuid,
    code text not null,
    name text not null,
    managerial_type text not null check (managerial_type in (
        'RECEITA','CUSTO','DESPESA','INVESTIMENTO','FINANCIAMENTO',
        'TRANSFERENCIA','SALDO_INICIAL','OUTRO'
    )),
    nature text not null check (nature in ('ENTRADA','SAIDA','NEUTRA')),
    participates_dre boolean not null default true,
    participates_cashflow boolean not null default true,
    requires_farm boolean not null default false,
    allows_allocation boolean not null default true,
    requires_crop_season boolean not null default false,
    display_order integer not null default 0,
    unique (template_id, code),
    unique (id, template_id),
    foreign key (parent_item_id, template_id)
        references public.chart_account_template_items(id, template_id)
);

create table public.chart_accounts (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    parent_id uuid,
    code text not null,
    name text not null,
    managerial_type text not null check (managerial_type in (
        'RECEITA','CUSTO','DESPESA','INVESTIMENTO','FINANCIAMENTO',
        'TRANSFERENCIA','SALDO_INICIAL','OUTRO'
    )),
    nature text not null check (nature in ('ENTRADA','SAIDA','NEUTRA')),
    participates_dre boolean not null default true,
    participates_cashflow boolean not null default true,
    requires_farm boolean not null default false,
    allows_allocation boolean not null default true,
    requires_crop_season boolean not null default false,
    display_order integer not null default 0,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, code),
    unique (id, organization_id),
    foreign key (parent_id, organization_id)
        references public.chart_accounts(id, organization_id)
);

create table public.parties (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    name text not null,
    tax_id text,
    party_type text not null check (party_type in ('FORNECEDOR','CLIENTE','AMBOS','BENEFICIARIO','OUTRO')),
    email text,
    phone text,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, organization_id)
);

create table public.bank_accounts (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    farm_id uuid,
    bank_code text,
    bank_name text not null,
    branch_number text,
    account_number text not null,
    account_type text,
    opening_balance numeric(18,2) not null default 0,
    opening_balance_date date,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, organization_id),
    foreign key (farm_id, organization_id)
        references public.farms(id, organization_id)
);

create table public.payment_methods (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    name text not null,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, name),
    unique (id, organization_id)
);

-- =========================================================
-- ALLOCATION ENGINE
-- =========================================================

create table public.allocation_rules (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    crop_season_id uuid not null,
    name text not null,
    description text,
    -- Start inactive so users can compose percentages transactionally before activation.
    is_active boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, crop_season_id, name),
    unique (id, organization_id),
    foreign key (crop_season_id, organization_id)
        references public.crop_seasons(id, organization_id)
);

create table public.allocation_rule_items (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    allocation_rule_id uuid not null,
    farm_id uuid not null,
    percentage numeric(9,6) not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (allocation_rule_id, farm_id),
    unique (id, organization_id),
    foreign key (allocation_rule_id, organization_id)
        references public.allocation_rules(id, organization_id)
        on delete cascade,
    foreign key (farm_id, organization_id)
        references public.farms(id, organization_id),
    check (percentage > 0 and percentage <= 100)
);

-- =========================================================
-- INSTALLMENTS / FINANCIAL ENTRIES
-- =========================================================

create table public.installment_plans (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    description text not null,
    total_amount numeric(18,2) not null,
    installment_count integer not null,
    first_due_date date,
    notes text,
    created_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, organization_id),
    check (total_amount > 0),
    check (installment_count > 0)
);

create table public.financial_entries (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    entry_direction text not null check (entry_direction in ('ENTRADA','SAIDA')),
    status text not null default 'PENDENTE' check (status in ('PENDENTE','AGENDADO','PAGO')),
    issue_date date not null,
    due_date date not null,
    document_number text,
    document_name text,
    description text not null,
    counterparty_id uuid,
    chart_account_id uuid not null,
    crop_season_id uuid,
    payment_method_id uuid,
    planned_bank_account_id uuid,
    amount numeric(18,2) not null,
    installment_plan_id uuid,
    installment_number integer,
    installment_total integer,
    source_type text not null default 'MANUAL' check (source_type in ('MANUAL','IMPORTACAO','PARCELAMENTO','FINANCIAMENTO','SISTEMA')),
    reversal_of_entry_id uuid,
    notes text,
    created_by uuid references auth.users(id),
    updated_by uuid references auth.users(id),
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, organization_id),
    foreign key (counterparty_id, organization_id)
        references public.parties(id, organization_id),
    foreign key (chart_account_id, organization_id)
        references public.chart_accounts(id, organization_id),
    foreign key (crop_season_id, organization_id)
        references public.crop_seasons(id, organization_id),
    foreign key (payment_method_id, organization_id)
        references public.payment_methods(id, organization_id),
    foreign key (planned_bank_account_id, organization_id)
        references public.bank_accounts(id, organization_id),
    foreign key (installment_plan_id, organization_id)
        references public.installment_plans(id, organization_id),
    foreign key (reversal_of_entry_id, organization_id)
        references public.financial_entries(id, organization_id),
    check (amount > 0),
    check (
        (installment_plan_id is null and installment_number is null and installment_total is null)
        or
        (installment_plan_id is not null and installment_number between 1 and installment_total and installment_total > 0)
    )
);

-- NOTE: due_date may legitimately precede issue_date in imported/historical corrections,
-- so no strict chronological CHECK is enforced in v0.2.

create table public.entry_allocations (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    financial_entry_id uuid not null,
    farm_id uuid not null,
    allocation_rule_id uuid,
    percentage numeric(9,6) not null,
    allocated_amount numeric(18,2) not null,
    snapshot_rule_name text,
    snapshot_crop_season_name text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (financial_entry_id, farm_id),
    unique (id, organization_id),
    foreign key (financial_entry_id, organization_id)
        references public.financial_entries(id, organization_id)
        on delete cascade,
    foreign key (farm_id, organization_id)
        references public.farms(id, organization_id),
    foreign key (allocation_rule_id, organization_id)
        references public.allocation_rules(id, organization_id),
    check (percentage > 0 and percentage <= 100),
    check (allocated_amount >= 0)
);

create table public.settlements (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    financial_entry_id uuid not null,
    bank_account_id uuid not null,
    settled_at timestamptz not null,
    amount numeric(18,2) not null,
    reference text,
    notes text,
    created_by uuid references auth.users(id),
    reversed_at timestamptz,
    reversed_by uuid references auth.users(id),
    reversal_reason text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, organization_id),
    foreign key (financial_entry_id, organization_id)
        references public.financial_entries(id, organization_id),
    foreign key (bank_account_id, organization_id)
        references public.bank_accounts(id, organization_id),
    check (amount > 0),
    check (
        (reversed_at is null and reversed_by is null)
        or
        (reversed_at is not null and reversed_by is not null and reversal_reason is not null and length(trim(reversal_reason)) > 0)
    )
);

-- =========================================================
-- FINANCING
-- =========================================================

create table public.financing_contracts (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    creditor_party_id uuid,
    bank_account_id uuid,
    contract_number text not null,
    issued_on date not null,
    credit_date date,
    contracted_amount numeric(18,2) not null,
    installment_count integer not null,
    credit_entry_id uuid,
    notes text,
    created_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, contract_number),
    unique (id, organization_id),
    foreign key (creditor_party_id, organization_id)
        references public.parties(id, organization_id),
    foreign key (bank_account_id, organization_id)
        references public.bank_accounts(id, organization_id),
    foreign key (credit_entry_id, organization_id)
        references public.financial_entries(id, organization_id),
    check (contracted_amount > 0),
    check (installment_count > 0)
);

create table public.financing_installments (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    financing_contract_id uuid not null,
    installment_number integer not null,
    due_date date not null,
    principal_amount numeric(18,2) not null default 0,
    interest_amount numeric(18,2) not null default 0,
    other_charges_amount numeric(18,2) not null default 0,
    principal_entry_id uuid,
    interest_entry_id uuid,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (financing_contract_id, installment_number),
    unique (id, organization_id),
    foreign key (financing_contract_id, organization_id)
        references public.financing_contracts(id, organization_id)
        on delete cascade,
    foreign key (principal_entry_id, organization_id)
        references public.financial_entries(id, organization_id),
    foreign key (interest_entry_id, organization_id)
        references public.financial_entries(id, organization_id),
    check (installment_number > 0),
    check (principal_amount >= 0),
    check (interest_amount >= 0),
    check (other_charges_amount >= 0)
);

-- =========================================================
-- BUDGET / FORECAST
-- =========================================================

create table public.budgets (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    name text not null,
    budget_type text not null check (budget_type in ('DRE','DFC')),
    calendar_year integer,
    crop_season_id uuid,
    status text not null default 'RASCUNHO' check (status in ('RASCUNHO','ATIVO','ARQUIVADO')),
    created_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, organization_id),
    foreign key (crop_season_id, organization_id)
        references public.crop_seasons(id, organization_id)
);

create table public.budget_items (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    budget_id uuid not null,
    period_month date not null,
    chart_account_id uuid not null,
    crop_season_id uuid,
    amount numeric(18,2) not null,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, organization_id),
    foreign key (budget_id, organization_id)
        references public.budgets(id, organization_id)
        on delete cascade,
    foreign key (chart_account_id, organization_id)
        references public.chart_accounts(id, organization_id),
    foreign key (crop_season_id, organization_id)
        references public.crop_seasons(id, organization_id),
    check (amount >= 0),
    check (date_trunc('month', period_month)::date = period_month)
);

create table public.budget_item_allocations (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    budget_item_id uuid not null,
    farm_id uuid not null,
    allocation_rule_id uuid,
    percentage numeric(9,6) not null,
    allocated_amount numeric(18,2) not null,
    snapshot_rule_name text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (budget_item_id, farm_id),
    unique (id, organization_id),
    foreign key (budget_item_id, organization_id)
        references public.budget_items(id, organization_id)
        on delete cascade,
    foreign key (farm_id, organization_id)
        references public.farms(id, organization_id),
    foreign key (allocation_rule_id, organization_id)
        references public.allocation_rules(id, organization_id),
    check (percentage > 0 and percentage <= 100),
    check (allocated_amount >= 0)
);

-- =========================================================
-- AUDIT
-- =========================================================

create table public.audit_logs (
    id bigint generated always as identity primary key,
    organization_id uuid not null references public.organizations(id),
    actor_user_id uuid,
    entity_type text not null,
    entity_id uuid,
    action text not null,
    old_data jsonb,
    new_data jsonb,
    request_id uuid,
    created_at timestamptz not null default now()
);

-- =========================================================
-- INDEXES
-- =========================================================

create index idx_memberships_user_org
    on public.memberships(user_id, organization_id)
    where is_active = true;

create index idx_financial_entries_org_issue
    on public.financial_entries(organization_id, issue_date)
    where deleted_at is null;

create index idx_financial_entries_org_due
    on public.financial_entries(organization_id, due_date)
    where deleted_at is null;

create index idx_financial_entries_org_status_due
    on public.financial_entries(organization_id, status, due_date)
    where deleted_at is null;

create index idx_financial_entries_org_account_issue
    on public.financial_entries(organization_id, chart_account_id, issue_date)
    where deleted_at is null;

create index idx_financial_entries_org_season_issue
    on public.financial_entries(organization_id, crop_season_id, issue_date)
    where deleted_at is null;

create index idx_entry_allocations_org_farm_entry
    on public.entry_allocations(organization_id, farm_id, financial_entry_id);

create index idx_settlements_org_settled
    on public.settlements(organization_id, settled_at)
    where reversed_at is null;

create index idx_settlements_org_entry
    on public.settlements(organization_id, financial_entry_id)
    where reversed_at is null;

create index idx_settlements_org_bank_date
    on public.settlements(organization_id, bank_account_id, settled_at)
    where reversed_at is null;

create index idx_budget_items_org_budget_month
    on public.budget_items(organization_id, budget_id, period_month);

create index idx_audit_logs_org_created
    on public.audit_logs(organization_id, created_at desc);
