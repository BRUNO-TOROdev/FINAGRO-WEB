-- FINAGRO Web — Chart of accounts and allocation configuration integration tests.
begin;

create schema test_support;
create function test_support.assert_true(condition boolean, message text)
returns void language plpgsql set search_path = '' as $$
begin
    if condition is not true then raise exception 'TEST FAILED: %', message; end if;
end;
$$;
create function test_support.expect_error(statement text, expected_message text)
returns void language plpgsql set search_path = '' as $$
declare actual_message text;
begin
    begin
        execute statement;
        set constraints all immediate;
    exception when others then
        actual_message := sqlerrm;
        set constraints all deferred;
        if position(expected_message in actual_message) = 0 then
            raise exception 'TEST FAILED: expected "%", got "%"', expected_message, actual_message;
        end if;
        return;
    end;
    raise exception 'TEST FAILED: expected error "%"', expected_message;
end;
$$;
grant usage on schema test_support to authenticated;
grant execute on all functions in schema test_support to authenticated;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
('71000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','config-a@example.test','unused',now(),'{}','{}',now(),now()),
('72000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','config-b@example.test','unused',now(),'{}','{}',now(),now());
insert into public.organizations (id, legal_name) values
('71000000-0000-0000-0000-000000000010','CONFIG A'),
('72000000-0000-0000-0000-000000000020','CONFIG B');
select private.seed_default_roles('71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-000000000001');
select private.seed_default_roles('72000000-0000-0000-0000-000000000020','72000000-0000-0000-0000-000000000002');

insert into public.chart_accounts (id,organization_id,code,name,managerial_type,nature,parent_id,display_order) values
('71000000-0000-0000-0000-000000000101','71000000-0000-0000-0000-000000000010','1','Raiz','RECEITA','ENTRADA',null,1),
('71000000-0000-0000-0000-000000000102','71000000-0000-0000-0000-000000000010','1.1','Filha','RECEITA','ENTRADA','71000000-0000-0000-0000-000000000101',1),
('71000000-0000-0000-0000-000000000103','71000000-0000-0000-0000-000000000010','1.1.1','Neta','RECEITA','ENTRADA','71000000-0000-0000-0000-000000000102',1),
('72000000-0000-0000-0000-000000000201','72000000-0000-0000-0000-000000000020','1','Conta B','RECEITA','ENTRADA',null,1);

select test_support.assert_true((select level from public.chart_accounts where id='71000000-0000-0000-0000-000000000101')=1,'root level');
select test_support.assert_true((select level from public.chart_accounts where id='71000000-0000-0000-0000-000000000103')=3,'grandchild level');
select test_support.expect_error($$insert into public.chart_accounts(id,organization_id,parent_id,code,name,managerial_type,nature) values('71000000-0000-0000-0000-000000000104','71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-999999999999','X','Órfã','OUTRO','NEUTRA')$$,'CHART_ACCOUNT_PARENT_NOT_FOUND');
select test_support.expect_error($$insert into public.chart_accounts(id,organization_id,parent_id,code,name,managerial_type,nature) values('71000000-0000-0000-0000-000000000105','71000000-0000-0000-0000-000000000010','72000000-0000-0000-0000-000000000201','X','Cross','OUTRO','NEUTRA')$$,'CHART_ACCOUNT_PARENT_NOT_FOUND');
select test_support.expect_error($$insert into public.chart_accounts(id,organization_id,parent_id,code,name,managerial_type,nature) values('71000000-0000-0000-0000-000000000106','71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-000000000106','X','Self','OUTRO','NEUTRA')$$,'CHART_ACCOUNT_CANNOT_PARENT_ITSELF');
select test_support.expect_error($$update public.chart_accounts set parent_id='71000000-0000-0000-0000-000000000103' where id='71000000-0000-0000-0000-000000000101'$$,'CHART_ACCOUNT_HIERARCHY_CYCLE');
select test_support.expect_error($$insert into public.chart_accounts(organization_id,code,name,managerial_type,nature) values('71000000-0000-0000-0000-000000000010','1','Duplicada','OUTRO','NEUTRA')$$,'chart_accounts_organization_id_code_key');

update public.chart_accounts set parent_id=null where id='71000000-0000-0000-0000-000000000102';
select test_support.assert_true((select level from public.chart_accounts where id='71000000-0000-0000-0000-000000000102')=1,'reparented child level');
select test_support.assert_true((select level from public.chart_accounts where id='71000000-0000-0000-0000-000000000103')=2,'descendant level refreshed');
update public.chart_accounts set is_active=false where id='71000000-0000-0000-0000-000000000103';
select test_support.assert_true(exists(select 1 from public.chart_accounts where id='71000000-0000-0000-0000-000000000103' and not is_active),'inactivation preserves row');

insert into public.farms(id,organization_id,name) values
('71000000-0000-0000-0000-000000000301','71000000-0000-0000-0000-000000000010','A1'),
('71000000-0000-0000-0000-000000000302','71000000-0000-0000-0000-000000000010','A2'),
('72000000-0000-0000-0000-000000000303','72000000-0000-0000-0000-000000000020','B1');
insert into public.crop_seasons(id,organization_id,name,season_type) values
('71000000-0000-0000-0000-000000000401','71000000-0000-0000-0000-000000000010','Safra A','PRINCIPAL'),
('72000000-0000-0000-0000-000000000402','72000000-0000-0000-0000-000000000020','Safra B','PRINCIPAL');
insert into public.allocation_rules(id,organization_id,crop_season_id,name) values
('71000000-0000-0000-0000-000000000501','71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-000000000401','Rascunho 99,99'),
('72000000-0000-0000-0000-000000000502','72000000-0000-0000-0000-000000000020','72000000-0000-0000-0000-000000000402','Regra B');
insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage) values
('71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-000000000501','71000000-0000-0000-0000-000000000301',50),
('71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-000000000501','71000000-0000-0000-0000-000000000302',49.99),
('72000000-0000-0000-0000-000000000020','72000000-0000-0000-0000-000000000502','72000000-0000-0000-0000-000000000303',100);
select test_support.expect_error($$update public.allocation_rules set is_active=true where id='71000000-0000-0000-0000-000000000501'$$,'ALLOCATION_RULE_MUST_TOTAL_100');
update public.allocation_rule_items set percentage=50 where allocation_rule_id='71000000-0000-0000-0000-000000000501' and farm_id='71000000-0000-0000-0000-000000000302';
update public.allocation_rules set is_active=true where id='71000000-0000-0000-0000-000000000501';
set constraints all immediate;
set constraints all deferred;
select test_support.assert_true((select is_active from public.allocation_rules where id='71000000-0000-0000-0000-000000000501'),'100 percent activates');
select test_support.expect_error($$insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage) values('71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-000000000501','71000000-0000-0000-0000-000000000301',-1)$$,'allocation_rule_items_percentage_check');
select test_support.expect_error($$insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage) values('71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-000000000501','71000000-0000-0000-0000-000000000301',101)$$,'allocation_rule_items_percentage_check');
select test_support.expect_error($$insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage) values('71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-000000000501','71000000-0000-0000-0000-000000000301',1)$$,'allocation_rule_items_allocation_rule_id_farm_id_key');
select test_support.expect_error($$insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage) values('71000000-0000-0000-0000-000000000010','71000000-0000-0000-0000-000000000501','72000000-0000-0000-0000-000000000303',1)$$,'allocation_rule_items_farm_id_organization_id_fkey');
select test_support.expect_error($$insert into public.allocation_rules(organization_id,crop_season_id,name) values('71000000-0000-0000-0000-000000000010','72000000-0000-0000-0000-000000000402','Cross season')$$,'allocation_rules_crop_season_id_organization_id_fkey');

insert into public.chart_account_templates(id,name,version) values('73000000-0000-0000-0000-000000000001','TEST TEMPLATE','test-only');
insert into public.chart_account_template_items(id,template_id,parent_item_id,code,name,managerial_type,nature,display_order) values
('73000000-0000-0000-0000-000000000011','73000000-0000-0000-0000-000000000001',null,'T','Test root','OUTRO','NEUTRA',1),
('73000000-0000-0000-0000-000000000012','73000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000011','T.1','Test child','OUTRO','NEUTRA',1);

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000001',true);
select test_support.assert_true(public.apply_chart_account_template('71000000-0000-0000-0000-000000000010','73000000-0000-0000-0000-000000000001'),'template first application');
select test_support.assert_true(not public.apply_chart_account_template('71000000-0000-0000-0000-000000000010','73000000-0000-0000-0000-000000000001'),'template application idempotent');
select test_support.assert_true((select count(*) from public.chart_accounts where organization_id='71000000-0000-0000-0000-000000000010' and source_template_id='73000000-0000-0000-0000-000000000001')=2,'template copied two accounts');
select test_support.expect_error($$select public.save_allocation_rule('72000000-0000-0000-0000-000000000020',null,'Cross','72000000-0000-0000-0000-000000000402',null,false,'[{"farm_id":"72000000-0000-0000-0000-000000000303","percentage":"100"}]')$$,'PERMISSION_DENIED');
select test_support.assert_true((select count(*) from public.chart_accounts where organization_id='72000000-0000-0000-0000-000000000020')=0,'A cannot view B chart accounts');
select test_support.assert_true((select count(*) from public.allocation_rules where organization_id='72000000-0000-0000-0000-000000000020')=0,'A cannot view B allocation rules');
update public.chart_accounts set name='INVASÃO' where id='72000000-0000-0000-0000-000000000201';
update public.allocation_rules set name='INVASÃO' where id='72000000-0000-0000-0000-000000000502';

reset role;
select test_support.assert_true((select name from public.chart_accounts where id='72000000-0000-0000-0000-000000000201')='Conta B','A cannot update B chart');
select test_support.assert_true((select name from public.allocation_rules where id='72000000-0000-0000-0000-000000000502')='Regra B','A cannot update B rule');

rollback;
