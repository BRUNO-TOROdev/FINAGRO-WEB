-- FINAGRO Web — smoke tests de invariantes (executar em Supabase local como postgres)
-- Estes testes não substituem os testes RLS autenticados descritos em TEST_PLAN.md.

begin;

-- Fixtures independentes de auth.users.
insert into public.organizations (id, legal_name)
values ('00000000-0000-0000-0000-000000000101', 'ORG TESTE A');

insert into public.farms (id, organization_id, name) values
('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000101', 'FAZENDA A'),
('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000101', 'FAZENDA B'),
('00000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000101', 'FAZENDA C');

insert into public.crop_seasons (id, organization_id, name, season_type)
values ('00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000101', 'SAFRA TESTE 26/27', 'PRINCIPAL');

insert into public.chart_accounts (
    id, organization_id, code, name, managerial_type, nature,
    participates_dre, participates_cashflow, allows_allocation, requires_crop_season
) values (
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000101',
    '3.1.01', 'Despesa Teste', 'DESPESA', 'SAIDA', true, true, true, true
);

-- Active rule 45/40/15.
insert into public.allocation_rules (
    id, organization_id, crop_season_id, name, is_active
) values (
    '00000000-0000-0000-0000-000000000501',
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000301',
    'RATEIO TESTE', false
);

insert into public.allocation_rule_items (organization_id, allocation_rule_id, farm_id, percentage) values
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000201',45.000000),
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000202',40.000000),
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000203',15.000000);

update public.allocation_rules
set is_active = true
where id = '00000000-0000-0000-0000-000000000501';

-- Entry + allocation must be created in one transaction because the allocation
-- balance constraint is DEFERRABLE INITIALLY DEFERRED.
insert into public.financial_entries (
    id, organization_id, entry_direction, status, issue_date, due_date,
    description, chart_account_id, crop_season_id, amount
) values (
    '00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-000000000101',
    'SAIDA', 'PENDENTE', date '2026-09-01', date '2026-10-01',
    'Lançamento rateado', '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000301', 100000.00
);

-- As postgres/service context, direct function permission checks pass only if auth.role()
-- is service_role. For smoke SQL, insert the snapshot explicitly.
insert into public.entry_allocations (
    organization_id, financial_entry_id, farm_id, allocation_rule_id,
    percentage, allocated_amount, snapshot_rule_name, snapshot_crop_season_name
) values
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000601','00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000501',45.000000,45000.00,'RATEIO TESTE','SAFRA TESTE 26/27'),
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000601','00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000501',40.000000,40000.00,'RATEIO TESTE','SAFRA TESTE 26/27'),
('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000601','00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000501',15.000000,15000.00,'RATEIO TESTE','SAFRA TESTE 26/27');

set constraints all immediate;

-- Assertions.
do $$
declare
    v_pct numeric;
    v_amt numeric;
begin
    select sum(percentage), sum(allocated_amount)
      into v_pct, v_amt
      from public.entry_allocations
     where financial_entry_id = '00000000-0000-0000-0000-000000000601';

    if v_pct <> 100.000000 then
        raise exception 'TEST FAILED: allocation percent = %', v_pct;
    end if;
    if v_amt <> 100000.00 then
        raise exception 'TEST FAILED: allocation amount = %', v_amt;
    end if;
end $$;

-- Verify signed reporting semantics for a SAIDA.
do $$
declare
    v_signed numeric;
begin
    select sum(signed_allocated_amount)
      into v_signed
      from public.v_entry_allocated_amounts
     where financial_entry_id = '00000000-0000-0000-0000-000000000601';
    if v_signed <> -100000.00 then
        raise exception 'TEST FAILED: signed amount = %', v_signed;
    end if;
end $$;

rollback;
