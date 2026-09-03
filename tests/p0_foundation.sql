-- FINAGRO Web — deterministic P0 integration tests
-- Runs against Supabase local as postgres, but all RLS assertions switch to the
-- authenticated database role and provide real auth.uid()/auth.role() JWT claims.

begin;

create schema test_support;

create function test_support.assert_true(condition boolean, message text)
returns void language plpgsql set search_path = '' as $$
begin
    if condition is not true then
        raise exception 'TEST FAILED: %', message;
    end if;
end;
$$;

create function test_support.expect_error(statement text, expected_message text)
returns void language plpgsql set search_path = '' as $$
declare
    actual_message text;
begin
    begin
        execute statement;
        set constraints all immediate;
    exception when others then
        actual_message := sqlerrm;
        set constraints all deferred;
        if position(expected_message in actual_message) = 0 then
            raise exception 'TEST FAILED: expected error containing "%", got "%"',
                expected_message, actual_message;
        end if;
        return;
    end;
    raise exception 'TEST FAILED: statement succeeded; expected error containing "%": %',
        expected_message, statement;
end;
$$;

grant usage on schema test_support to authenticated;
grant execute on function test_support.assert_true(boolean, text) to authenticated;
grant execute on function test_support.expect_error(text, text) to authenticated;

-- Stable IDs: 1xxx = organization A, 2xxx = organization B.
insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
('00000000-0000-0000-0000-000000001001', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'user-a@example.test', 'not-used', now(), '{}', '{}', now(), now()),
('00000000-0000-0000-0000-000000002001', '00000000-0000-0000-0000-000000000000',
 'authenticated', 'authenticated', 'user-b@example.test', 'not-used', now(), '{}', '{}', now(), now());

insert into public.organizations (id, legal_name) values
('00000000-0000-0000-0000-000000001010', 'ORGANIZAÇÃO A'),
('00000000-0000-0000-0000-000000002010', 'ORGANIZAÇÃO B');

select private.seed_default_roles(
    '00000000-0000-0000-0000-000000001010',
    '00000000-0000-0000-0000-000000001001'
);
select private.seed_default_roles(
    '00000000-0000-0000-0000-000000002010',
    '00000000-0000-0000-0000-000000002001'
);

insert into public.farms (id, organization_id, name) values
('00000000-0000-0000-0000-000000001101','00000000-0000-0000-0000-000000001010','A1'),
('00000000-0000-0000-0000-000000001102','00000000-0000-0000-0000-000000001010','A2'),
('00000000-0000-0000-0000-000000001103','00000000-0000-0000-0000-000000001010','A3'),
('00000000-0000-0000-0000-000000002101','00000000-0000-0000-0000-000000002010','B1');

insert into public.crop_seasons (id, organization_id, name, season_type) values
('00000000-0000-0000-0000-000000001201','00000000-0000-0000-0000-000000001010','2026/27','PRINCIPAL'),
('00000000-0000-0000-0000-000000001202','00000000-0000-0000-0000-000000001010','2027/28','PRINCIPAL'),
('00000000-0000-0000-0000-000000002201','00000000-0000-0000-0000-000000002010','2026/27 B','PRINCIPAL');

insert into public.chart_accounts (
    id, organization_id, code, name, managerial_type, nature,
    participates_dre, participates_cashflow, allows_allocation, requires_crop_season, is_active
) values
('00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001010','3.1','Despesa A','DESPESA','SAIDA',true,true,true,true,true),
('00000000-0000-0000-0000-000000001302','00000000-0000-0000-0000-000000001010','3.2','Inativa A','DESPESA','SAIDA',true,true,true,false,false),
('00000000-0000-0000-0000-000000001303','00000000-0000-0000-0000-000000001010','3.3','Sem rateio A','DESPESA','SAIDA',true,true,false,false,true),
('00000000-0000-0000-0000-000000002301','00000000-0000-0000-0000-000000002010','3.1','Despesa B','DESPESA','SAIDA',true,true,true,true,true);

insert into public.parties (id, organization_id, name, party_type) values
('00000000-0000-0000-0000-000000001401','00000000-0000-0000-0000-000000001010','Fornecedor A','FORNECEDOR'),
('00000000-0000-0000-0000-000000002401','00000000-0000-0000-0000-000000002010','Fornecedor B','FORNECEDOR');

insert into public.bank_accounts (id, organization_id, bank_name, account_number) values
('00000000-0000-0000-0000-000000001501','00000000-0000-0000-0000-000000001010','Banco A','1'),
('00000000-0000-0000-0000-000000002501','00000000-0000-0000-0000-000000002010','Banco B','1');

insert into public.payment_methods (id, organization_id, name) values
('00000000-0000-0000-0000-000000001601','00000000-0000-0000-0000-000000001010','PIX A'),
('00000000-0000-0000-0000-000000002601','00000000-0000-0000-0000-000000002010','PIX B');

-- Rules: canonical snapshot, invalid draft, rounding, and tenant B.
insert into public.allocation_rules (id, organization_id, crop_season_id, name) values
('00000000-0000-0000-0000-000000001701','00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001201','45-40-15'),
('00000000-0000-0000-0000-000000001702','00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001201','99,99'),
('00000000-0000-0000-0000-000000001703','00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001201','TERÇOS'),
('00000000-0000-0000-0000-000000002701','00000000-0000-0000-0000-000000002010','00000000-0000-0000-0000-000000002201','B 100');

insert into public.allocation_rule_items (organization_id, allocation_rule_id, farm_id, percentage) values
('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001701','00000000-0000-0000-0000-000000001101',45),
('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001701','00000000-0000-0000-0000-000000001102',40),
('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001701','00000000-0000-0000-0000-000000001103',15),
('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001702','00000000-0000-0000-0000-000000001101',99.99),
('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001703','00000000-0000-0000-0000-000000001101',33.333333),
('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001703','00000000-0000-0000-0000-000000001102',33.333333),
('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001703','00000000-0000-0000-0000-000000001103',33.333334),
('00000000-0000-0000-0000-000000002010','00000000-0000-0000-0000-000000002701','00000000-0000-0000-0000-000000002101',100);

update public.allocation_rules set is_active = true
where id in ('00000000-0000-0000-0000-000000001701','00000000-0000-0000-0000-000000001703','00000000-0000-0000-0000-000000002701');
set constraints all immediate;
set constraints all deferred;

-- Drafts may be incomplete; invalid individual percentages and 99.99 activation fail.
select test_support.expect_error(
    $$update public.allocation_rules set is_active=true where id='00000000-0000-0000-0000-000000001702'$$,
    'ALLOCATION_RULE_MUST_TOTAL_100'
);
select test_support.expect_error(
    $$insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage)
      values('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001702','00000000-0000-0000-0000-000000001102',0)$$,
    'allocation_rule_items_percentage_check'
);
select test_support.expect_error(
    $$insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage)
      values('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001702','00000000-0000-0000-0000-000000001102',100.000001)$$,
    'allocation_rule_items_percentage_check'
);

-- Cross-tenant composed FKs for rule farm and season.
select test_support.expect_error(
    $$insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage)
      values('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001702','00000000-0000-0000-0000-000000002101',0.01)$$,
    'allocation_rule_items_farm_id_organization_id_fkey'
);
select test_support.expect_error(
    $$insert into public.allocation_rules(organization_id,crop_season_id,name)
      values('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000002201','CROSS')$$,
    'allocation_rules_crop_season_id_organization_id_fkey'
);

-- Base entries for both organizations.
insert into public.financial_entries (
 id,organization_id,entry_direction,status,issue_date,due_date,description,counterparty_id,
 chart_account_id,crop_season_id,payment_method_id,planned_bank_account_id,amount,created_by
) values
('00000000-0000-0000-0000-000000001801','00000000-0000-0000-0000-000000001010','SAIDA','PENDENTE','2026-09-01','2026-10-01','Snapshot antigo','00000000-0000-0000-0000-000000001401','00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001201','00000000-0000-0000-0000-000000001601','00000000-0000-0000-0000-000000001501',100000,'00000000-0000-0000-0000-000000001001'),
('00000000-0000-0000-0000-000000001802','00000000-0000-0000-0000-000000001010','SAIDA','PENDENTE','2026-09-02','2026-10-02','Arredondamento',null,'00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001201',null,null,100,'00000000-0000-0000-0000-000000001001'),
('00000000-0000-0000-0000-000000001803','00000000-0000-0000-0000-000000001010','SAIDA','PENDENTE','2026-09-03','2026-10-03','Direto',null,'00000000-0000-0000-0000-000000001303',null,null,null,200,'00000000-0000-0000-0000-000000001001'),
('00000000-0000-0000-0000-000000002801','00000000-0000-0000-0000-000000002010','SAIDA','PENDENTE','2026-09-01','2026-10-01','Entrada B','00000000-0000-0000-0000-000000002401','00000000-0000-0000-0000-000000002301','00000000-0000-0000-0000-000000002201','00000000-0000-0000-0000-000000002601','00000000-0000-0000-0000-000000002501',50,'00000000-0000-0000-0000-000000002001');

select public.apply_allocation_rule('00000000-0000-0000-0000-000000001801','00000000-0000-0000-0000-000000001701');
select public.apply_allocation_rule('00000000-0000-0000-0000-000000001802','00000000-0000-0000-0000-000000001703');
select public.apply_direct_farm_allocation('00000000-0000-0000-0000-000000001803','00000000-0000-0000-0000-000000001101');
select public.apply_direct_farm_allocation('00000000-0000-0000-0000-000000002801','00000000-0000-0000-0000-000000002101');
set constraints all immediate;
set constraints all deferred;

insert into public.settlements (id,organization_id,financial_entry_id,bank_account_id,settled_at,amount,created_by)
values ('00000000-0000-0000-0000-000000002901','00000000-0000-0000-0000-000000002010','00000000-0000-0000-0000-000000002801','00000000-0000-0000-0000-000000002501','2026-10-01 12:00Z',50,'00000000-0000-0000-0000-000000002001');

select test_support.assert_true(
    (select array_agg(allocated_amount order by farm_id) from public.entry_allocations where financial_entry_id='00000000-0000-0000-0000-000000001801')
    = array[45000.00,40000.00,15000.00]::numeric[], 'snapshot inicial 45/40/15'
);
select test_support.assert_true(
    (select sum(allocated_amount) from public.entry_allocations where financial_entry_id='00000000-0000-0000-0000-000000001802') = 100.00,
    'arredondamento soma exatamente 100'
);
select test_support.assert_true(
    (select allocated_amount from public.entry_allocations where financial_entry_id='00000000-0000-0000-0000-000000001802' order by farm_id desc limit 1) = 33.34,
    'resíduo fica deterministicamente na última fazenda'
);
select test_support.assert_true(
    (select percentage=100 and allocated_amount=200 from public.entry_allocations where financial_entry_id='00000000-0000-0000-0000-000000001803'),
    'apropriação direta 100%'
);

-- Change future rule to 40/40/20; old snapshot remains immutable.
update public.allocation_rule_items set percentage=40 where allocation_rule_id='00000000-0000-0000-0000-000000001701' and farm_id='00000000-0000-0000-0000-000000001101';
update public.allocation_rule_items set percentage=20 where allocation_rule_id='00000000-0000-0000-0000-000000001701' and farm_id='00000000-0000-0000-0000-000000001103';
set constraints all immediate;
set constraints all deferred;
select test_support.assert_true(
    (select array_agg(allocated_amount order by farm_id) from public.entry_allocations where financial_entry_id='00000000-0000-0000-0000-000000001801')
    = array[45000.00,40000.00,15000.00]::numeric[], 'alterar regra não muda snapshot histórico'
);

insert into public.financial_entries (id,organization_id,entry_direction,issue_date,due_date,description,chart_account_id,crop_season_id,amount)
values ('00000000-0000-0000-0000-000000001804','00000000-0000-0000-0000-000000001010','SAIDA','2026-09-04','2026-10-04','Snapshot novo','00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001201',100000);
select public.apply_allocation_rule('00000000-0000-0000-0000-000000001804','00000000-0000-0000-0000-000000001701');
set constraints all immediate;
set constraints all deferred;
select test_support.assert_true(
    (select array_agg(allocated_amount order by farm_id) from public.entry_allocations where financial_entry_id='00000000-0000-0000-0000-000000001804')
    = array[40000.00,40000.00,20000.00]::numeric[], 'novo snapshot 40/40/20'
);
select test_support.expect_error(
    $$update public.allocation_rules set crop_season_id='00000000-0000-0000-0000-000000001202' where id='00000000-0000-0000-0000-000000001701'$$,
    'USED_ALLOCATION_RULE_CROP_SEASON_IS_IMMUTABLE'
);

select test_support.expect_error($statement$
    do $block$
    begin
        insert into public.financial_entries(id,organization_id,entry_direction,issue_date,due_date,description,chart_account_id,crop_season_id,amount)
        values ('00000000-0000-0000-0000-000000001805','00000000-0000-0000-0000-000000001010','SAIDA','2026-09-05','2026-10-05','Duas diretas','00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001201',100);
        insert into public.entry_allocations(organization_id,financial_entry_id,farm_id,percentage,allocated_amount) values
        ('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001805','00000000-0000-0000-0000-000000001101',50,50),
        ('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001805','00000000-0000-0000-0000-000000001102',50,50);
    end
    $block$
$statement$, 'MULTI_FARM_ALLOCATION_REQUIRES_RULE');

select test_support.expect_error($statement$
    do $block$
    begin
        insert into public.financial_entries(id,organization_id,entry_direction,issue_date,due_date,description,chart_account_id,crop_season_id,amount)
        values ('00000000-0000-0000-0000-000000001806','00000000-0000-0000-0000-000000001010','SAIDA','2026-09-06','2026-10-06','Mistura','00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001201',100);
        insert into public.entry_allocations(organization_id,financial_entry_id,farm_id,allocation_rule_id,percentage,allocated_amount,snapshot_rule_name,snapshot_crop_season_name) values
        ('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001806','00000000-0000-0000-0000-000000001101','00000000-0000-0000-0000-000000001701',50,50,'45-40-15','2026/27'),
        ('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001806','00000000-0000-0000-0000-000000001102',null,50,50,null,null);
    end
    $block$
$statement$, 'ENTRY_ALLOCATION_CANNOT_MIX_DIRECT_AND_RULE');

insert into public.financial_entries(id,organization_id,entry_direction,issue_date,due_date,description,chart_account_id,crop_season_id,amount)
values ('00000000-0000-0000-0000-000000001807','00000000-0000-0000-0000-000000001010','SAIDA','2026-09-07','2026-10-07','Safra divergente','00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001202',100);
select test_support.expect_error(
    $$select public.apply_allocation_rule('00000000-0000-0000-0000-000000001807','00000000-0000-0000-0000-000000001701')$$,
    'ALLOCATION_RULE_SEASON_MUST_MATCH_ENTRY_SEASON'
);
update public.financial_entries set deleted_at=now() where id='00000000-0000-0000-0000-000000001807';

-- Account requirements and cross-tenant composed FK.
select test_support.expect_error(
    $$insert into public.financial_entries(organization_id,entry_direction,issue_date,due_date,description,chart_account_id,amount)
      values('00000000-0000-0000-0000-000000001010','SAIDA','2026-09-01','2026-09-01','Sem safra','00000000-0000-0000-0000-000000001301',1)$$,
    'CHART_ACCOUNT_REQUIRES_CROP_SEASON'
);
select test_support.expect_error(
    $$insert into public.financial_entries(organization_id,entry_direction,issue_date,due_date,description,chart_account_id,amount)
      values('00000000-0000-0000-0000-000000001010','SAIDA','2026-09-01','2026-09-01','Conta inativa','00000000-0000-0000-0000-000000001302',1)$$,
    'INACTIVE_CHART_ACCOUNT'
);
select test_support.expect_error(
    $$insert into public.financial_entries(organization_id,entry_direction,issue_date,due_date,description,chart_account_id,crop_season_id,amount)
      values('00000000-0000-0000-0000-000000001010','SAIDA','2026-09-01','2026-09-01','Conta B','00000000-0000-0000-0000-000000002301','00000000-0000-0000-0000-000000001201',1)$$,
    'INVALID_CHART_ACCOUNT'
);
update public.chart_accounts set is_active=false where id='00000000-0000-0000-0000-000000001301';
select test_support.assert_true(
    (select chart_account_id='00000000-0000-0000-0000-000000001301' from public.financial_entries where id='00000000-0000-0000-0000-000000001801'),
    'inativação não altera histórico'
);
update public.chart_accounts set is_active=true where id='00000000-0000-0000-0000-000000001301';

-- Status and settlements.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000001001","role":"authenticated"}',true);

select test_support.expect_error(
    $$update public.financial_entries set status='CANCELADO' where id='00000000-0000-0000-0000-000000001803'$$,
    'financial_entries_status_check'
);
select test_support.expect_error(
    $$update public.financial_entries set status='PAGO' where id='00000000-0000-0000-0000-000000001803'$$,
    'PAID_ENTRY_REQUIRES_FULL_SETTLEMENT'
);

insert into public.settlements (id,organization_id,financial_entry_id,bank_account_id,settled_at,amount,created_by)
values ('00000000-0000-0000-0000-000000001901','00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001803','00000000-0000-0000-0000-000000001501','2026-10-03 12:00Z',80,'00000000-0000-0000-0000-000000001001');
select test_support.assert_true((select status='PENDENTE' from public.financial_entries where id='00000000-0000-0000-0000-000000001803'),'parcial permanece pendente');
select test_support.expect_error(
    $$insert into public.settlements(organization_id,financial_entry_id,bank_account_id,settled_at,amount,created_by)
      values('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001803','00000000-0000-0000-0000-000000001501',now(),1,'00000000-0000-0000-0000-000000002001')$$,
    'SETTLEMENT_CREATED_BY_MUST_MATCH_CALLER'
);
select test_support.expect_error(
    $$insert into public.settlements(organization_id,financial_entry_id,bank_account_id,settled_at,amount,created_by)
      values('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001803','00000000-0000-0000-0000-000000001501',now(),121,'00000000-0000-0000-0000-000000001001')$$,
    'SETTLEMENTS_CANNOT_EXCEED_ENTRY_AMOUNT'
);
insert into public.settlements (id,organization_id,financial_entry_id,bank_account_id,settled_at,amount,created_by)
values ('00000000-0000-0000-0000-000000001902','00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001803','00000000-0000-0000-0000-000000001501','2026-10-03 13:00Z',120,'00000000-0000-0000-0000-000000001001');
select test_support.assert_true((select status='PAGO' from public.financial_entries where id='00000000-0000-0000-0000-000000001803'),'liquidação integral marca PAGO');
update public.settlements set amount=119 where id='00000000-0000-0000-0000-000000001902';
select test_support.assert_true((select amount=120 from public.settlements where id='00000000-0000-0000-0000-000000001902'),'liquidação não é editável diretamente');
select test_support.expect_error(
    $$select public.reverse_settlement('00000000-0000-0000-0000-000000001902','')$$,
    'REVERSAL_REASON_REQUIRED'
);
select public.reverse_settlement('00000000-0000-0000-0000-000000001902','correção determinística','AGENDADO');
select test_support.assert_true((select reversed_at is not null and reversed_by='00000000-0000-0000-0000-000000001001' from public.settlements where id='00000000-0000-0000-0000-000000001902'),'reversão registra usuário/data/motivo');
select test_support.assert_true((select status='AGENDADO' from public.financial_entries where id='00000000-0000-0000-0000-000000001803'),'reversão restaura AGENDADO');
update public.settlements set notes='editar' where id='00000000-0000-0000-0000-000000001902';
select test_support.assert_true((select notes is null from public.settlements where id='00000000-0000-0000-0000-000000001902'),'liquidação revertida permanece imutável');
update public.financial_entries set deleted_at=now() where id='00000000-0000-0000-0000-000000001804';
select test_support.expect_error(
    $$insert into public.settlements(organization_id,financial_entry_id,bank_account_id,settled_at,amount,created_by)
      values('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001804','00000000-0000-0000-0000-000000001501',now(),1,'00000000-0000-0000-0000-000000001001')$$,
    'ACTIVE_FINANCIAL_ENTRY_REQUIRED_FOR_SETTLEMENT'
);
select test_support.expect_error(
    $$insert into public.settlements(organization_id,financial_entry_id,bank_account_id,settled_at,amount,created_by)
      values('00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001803','00000000-0000-0000-0000-000000002501',now(),1,'00000000-0000-0000-0000-000000001001')$$,
    'settlements_bank_account_id_organization_id_fkey'
);

reset role;

-- Tenant-owned coverage fixtures for financing and budgets.
insert into public.financing_contracts (id,organization_id,contract_number,issued_on,contracted_amount,installment_count) values
('00000000-0000-0000-0000-000000001951','00000000-0000-0000-0000-000000001010','A-1','2026-09-01',1000,1),
('00000000-0000-0000-0000-000000002951','00000000-0000-0000-0000-000000002010','B-1','2026-09-01',1000,1);
insert into public.budgets (id,organization_id,name,budget_type,calendar_year) values
('00000000-0000-0000-0000-000000001961','00000000-0000-0000-0000-000000001010','Orçamento A','DRE',2026),
('00000000-0000-0000-0000-000000002961','00000000-0000-0000-0000-000000002010','Orçamento B','DRE',2026);
insert into public.budget_items (id,organization_id,budget_id,period_month,chart_account_id,crop_season_id,amount) values
('00000000-0000-0000-0000-000000001962','00000000-0000-0000-0000-000000001010','00000000-0000-0000-0000-000000001961','2026-09-01','00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001201',100),
('00000000-0000-0000-0000-000000002962','00000000-0000-0000-0000-000000002010','00000000-0000-0000-0000-000000002961','2026-09-01','00000000-0000-0000-0000-000000002301','00000000-0000-0000-0000-000000002201',100);

-- Parcel plan: only entries count financially; five parcels total exactly 500,000.
insert into public.installment_plans (id,organization_id,description,total_amount,installment_count,first_due_date) values
('00000000-0000-0000-0000-000000001970','00000000-0000-0000-0000-000000001010','Plano 5x',500000,5,'2026-10-01');
insert into public.financial_entries (
    id,organization_id,entry_direction,issue_date,due_date,description,chart_account_id,crop_season_id,
    amount,installment_plan_id,installment_number,installment_total,source_type
)
select ('00000000-0000-0000-0000-00000000197' || n)::uuid,
       '00000000-0000-0000-0000-000000001010','SAIDA','2026-09-01',
       (date '2026-10-01' + ((n-1) || ' month')::interval)::date,'Parcela '||n,
       '00000000-0000-0000-0000-000000001301','00000000-0000-0000-0000-000000001201',
       100000,'00000000-0000-0000-0000-000000001970',n,5,'PARCELAMENTO'
from generate_series(1,5) n;
insert into public.entry_allocations (organization_id,financial_entry_id,farm_id,percentage,allocated_amount)
select '00000000-0000-0000-0000-000000001010',
       ('00000000-0000-0000-0000-00000000197' || n)::uuid,
       '00000000-0000-0000-0000-000000001101',100,100000
from generate_series(1,5) n;
set constraints all immediate;
set constraints all deferred;
select test_support.assert_true(
    (select sum(allocated_amount) from public.v_entry_allocated_amounts where financial_entry_id in (
        select id from public.financial_entries where installment_plan_id='00000000-0000-0000-0000-000000001970'
    )) = 500000,
    'relatório soma parcelas uma vez, sem impacto do plano'
);
select test_support.expect_error(
    $$update public.installment_plans set total_amount=500001 where id='00000000-0000-0000-0000-000000001970'$$,
    'INSTALLMENT_TOTAL_MUST_MATCH_PLAN'
);

-- RLS as authenticated user A.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000001001","role":"authenticated"}',true);

select test_support.assert_true((select count(*) from public.farms where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B farms');
select test_support.assert_true((select count(*) from public.crop_seasons where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B crop seasons');
select test_support.assert_true((select count(*) from public.chart_accounts where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B chart accounts');
select test_support.assert_true((select count(*) from public.allocation_rules where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B allocation rules');
select test_support.assert_true((select count(*) from public.parties where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B parties');
select test_support.assert_true((select count(*) from public.bank_accounts where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B bank accounts');
select test_support.assert_true((select count(*) from public.financial_entries where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B entries');
select test_support.assert_true((select count(*) from public.entry_allocations where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B allocations');
select test_support.assert_true((select count(*) from public.settlements where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B settlements');
select test_support.assert_true((select count(*) from public.financing_contracts where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B financing');
select test_support.assert_true((select count(*) from public.budgets where organization_id='00000000-0000-0000-0000-000000002010')=0,'A cannot read B budgets');

select test_support.expect_error(
    $$insert into public.farms(organization_id,name) values('00000000-0000-0000-0000-000000002010','INVASÃO A')$$,
    'row-level security'
);

-- UPDATE against an invisible row returns zero rows, so prove no mutation explicitly.
update public.farms set name='INVASÃO A' where id='00000000-0000-0000-0000-000000002101';
select test_support.assert_true(not exists(select 1 from public.farms where id='00000000-0000-0000-0000-000000002101'),'A still cannot observe B after update attempt');
select test_support.expect_error(
    $$select public.apply_direct_farm_allocation('00000000-0000-0000-0000-000000002801','00000000-0000-0000-0000-000000002101')$$,
    'PERMISSION_DENIED'
);
select test_support.expect_error(
    $$select private.sync_entry_from_settlements('00000000-0000-0000-0000-000000002801')$$,
    'permission denied'
);

reset role;
select test_support.assert_true((select name='B1' from public.farms where id='00000000-0000-0000-0000-000000002101'),'A did not update B farm');

-- Inverse isolation as authenticated user B.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000002001","role":"authenticated"}',true);
select test_support.assert_true((select count(*) from public.farms where organization_id='00000000-0000-0000-0000-000000001010')=0,'B cannot read A farms');
select test_support.assert_true((select count(*) from public.financial_entries where organization_id='00000000-0000-0000-0000-000000001010')=0,'B cannot read A entries');
select test_support.assert_true((select count(*) from public.settlements where organization_id='00000000-0000-0000-0000-000000001010')=0,'B cannot read A settlements');
select test_support.assert_true((select count(*) from public.budgets where organization_id='00000000-0000-0000-0000-000000001010')=0,'B cannot read A budgets');
select test_support.expect_error(
    $$insert into public.parties(organization_id,name,party_type) values('00000000-0000-0000-0000-000000001010','INVASÃO B','OUTRO')$$,
    'row-level security'
);
select test_support.expect_error(
    $$select public.reverse_settlement('00000000-0000-0000-0000-000000001901','tentativa B')$$,
    'SETTLEMENT_NOT_FOUND'
);

reset role;

rollback;
