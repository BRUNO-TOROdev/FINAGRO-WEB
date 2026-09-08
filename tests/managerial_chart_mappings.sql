-- FINAGRO Web — managerial reporting mappings, hierarchy and tenant isolation.
begin;

create schema test_support;
create function test_support.assert_true(condition boolean,message text) returns void language plpgsql set search_path='' as $$
begin if condition is not true then raise exception 'TEST FAILED: %',message; end if; end$$;
create function test_support.expect_error(statement text,expected text) returns void language plpgsql set search_path='' as $$
declare msg text; begin begin execute statement; exception when others then msg=sqlerrm; if position(expected in msg)=0 then raise exception 'TEST FAILED: expected %, got %',expected,msg; end if; return; end; raise exception 'TEST FAILED: expected error %',expected; end$$;
grant usage on schema test_support to authenticated;
grant execute on all functions in schema test_support to authenticated;

select test_support.assert_true((select count(*) from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9')=154,'official chart still has 154 items');
select test_support.assert_true((select count(*) from public.reporting_templates)=5,'five managerial structures');
select test_support.assert_true(not exists(select 1 from public.report_account_template_mappings where confidence='inferred_needs_validation'),'inferred mappings are not operational');
select test_support.assert_true(not exists(select 1 from public.report_account_template_mappings m join public.report_line_templates l on l.id=m.report_line_template_id where l.line_type<>'ACCOUNT'),'calculated lines are not accounts');
select test_support.assert_true(not exists(select 1 from public.report_account_template_mappings where evidence ilike '%if account.name%'),'no name-based rule');

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('81000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','mapping-a@example.test','unused',now(),'{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','mapping-b@example.test','unused',now(),'{}','{}',now(),now());
insert into public.organizations(id,legal_name) values
('81000000-0000-0000-0000-000000000010','MAPPING A'),('82000000-0000-0000-0000-000000000020','MAPPING B');
select private.seed_default_roles('81000000-0000-0000-0000-000000000010','81000000-0000-0000-0000-000000000001');
select private.seed_default_roles('82000000-0000-0000-0000-000000000020','82000000-0000-0000-0000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
select test_support.assert_true(public.apply_chart_account_template('81000000-0000-0000-0000-000000000010','3269e51b-12de-5887-a85c-4461af91b4e9'),'A chart copied');
select test_support.assert_true(public.apply_reporting_template('81000000-0000-0000-0000-000000000010',(select id from public.reporting_templates where code='DRE')),'A DRE copied');
select test_support.assert_true(not public.apply_reporting_template('81000000-0000-0000-0000-000000000010',(select id from public.reporting_templates where code='DRE')),'A DRE copy is idempotent');
insert into public.chart_accounts(organization_id,code,name,managerial_type,nature) values('81000000-0000-0000-0000-000000000010','LOCAL-NEW','Nova sem mapping','OUTRO','NEUTRA');
select test_support.assert_true(not exists(select 1 from public.report_account_mappings m join public.chart_accounts a on a.id=m.chart_account_id where a.code='LOCAL-NEW'),'new account without mapping is harmless');
select test_support.expect_error($$insert into public.report_account_mappings(organization_id,reporting_structure_id,report_line_id,chart_account_id,managerial_role,recognition_basis) select '81000000-0000-0000-0000-000000000010',s.id,l.id,a.id,'TESTE','ISSUE_DATE' from public.reporting_structures s,public.report_lines l,public.chart_accounts a where s.organization_id='81000000-0000-0000-0000-000000000010' and s.code='DRE' and l.reporting_structure_id=s.id and l.line_type='ACCOUNT' and a.organization_id=s.organization_id limit 1$$,'report_account_mappings_organization_id_reporting_structure_key');

reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000002',true);
select test_support.assert_true(public.apply_chart_account_template('82000000-0000-0000-0000-000000000020','3269e51b-12de-5887-a85c-4461af91b4e9'),'B chart copied');
select test_support.assert_true(public.apply_reporting_template('82000000-0000-0000-0000-000000000020',(select id from public.reporting_templates where code='DRE')),'B DRE copied');
select test_support.assert_true((select count(*) from public.reporting_structures where organization_id='81000000-0000-0000-0000-000000000010')=0,'B cannot read A structures');

reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
select test_support.expect_error($$select public.apply_reporting_template('82000000-0000-0000-0000-000000000020',(select id from public.reporting_templates where code='DFC_PREVISTO'))$$,'PERMISSION_DENIED');
update public.report_account_mappings set evidence='Custom A' where id=(select id from public.report_account_mappings where organization_id='81000000-0000-0000-0000-000000000010' limit 1);
select test_support.assert_true(not exists(select 1 from public.report_account_mappings where organization_id='82000000-0000-0000-0000-000000000020' and evidence='Custom A'),'A mapping change does not alter B');
select test_support.assert_true(not exists(select 1 from public.report_account_template_mappings where evidence='Custom A'),'A mapping change does not alter template');

-- Explicit hierarchy guards, including calculated line not usable as an account target.
insert into public.report_lines(id,organization_id,reporting_structure_id,code,label,line_type,display_order,calculation)
select '81000000-0000-0000-0000-000000000101','81000000-0000-0000-0000-000000000010',id,'TEST.CALC','Calculada','CALCULATED',999999,'{"test":true}'::jsonb from public.reporting_structures where organization_id='81000000-0000-0000-0000-000000000010' and code='DRE';
select test_support.expect_error($$insert into public.report_account_mappings(organization_id,reporting_structure_id,report_line_id,chart_account_id,managerial_role,recognition_basis) select '81000000-0000-0000-0000-000000000010',s.id,'81000000-0000-0000-0000-000000000101',a.id,'TESTE','ISSUE_DATE' from public.reporting_structures s join public.chart_accounts a on a.organization_id=s.organization_id where s.organization_id='81000000-0000-0000-0000-000000000010' and s.code='DRE' limit 1$$,'REPORT_MAPPING_REQUIRES_ACCOUNT_LINE');
insert into public.report_lines(id,organization_id,reporting_structure_id,parent_id,code,label,line_type,display_order)
select '81000000-0000-0000-0000-000000000102','81000000-0000-0000-0000-000000000010',id,'81000000-0000-0000-0000-000000000101','TEST.CHILD','Filha','SECTION',1000000 from public.reporting_structures where organization_id='81000000-0000-0000-0000-000000000010' and code='DRE';
select test_support.expect_error($$update public.report_lines set parent_id='81000000-0000-0000-0000-000000000102' where id='81000000-0000-0000-0000-000000000101'$$,'REPORT_LINE_HIERARCHY_CYCLE');

rollback;
