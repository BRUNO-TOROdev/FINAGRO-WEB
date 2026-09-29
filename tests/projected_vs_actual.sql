-- FINAGRO Web — projected versus actual, explicit views and tenant safety.
begin;
create schema test_pva;
create function test_pva.ok(c boolean,m text) returns void language plpgsql set search_path='' as $$begin if c is not true then raise exception 'TEST FAILED: %',m;end if;end$$;
create function test_pva.err(q text,e text) returns void language plpgsql set search_path='' as $$declare m text;begin begin execute q;exception when others then m=sqlerrm;if position(e in m)=0 then raise exception 'TEST FAILED expected %, got %',e,m;end if;return;end;raise exception 'TEST FAILED expected %',e;end$$;
create function test_pva.metric(j jsonb,c text,m text,k text) returns numeric language sql immutable set search_path='' as $$select (x->'values'->$3->>$4)::numeric from jsonb_array_elements($1->'lines') x where x->>'code'=$2$$;
grant usage on schema test_pva to authenticated;grant execute on all functions in schema test_pva to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('aa000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pva-owner@example.test','x',now(),'{}','{}',now(),now()),
('aa000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pva-read@example.test','x',now(),'{}','{}',now(),now()),
('bb000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pva-other@example.test','x',now(),'{}','{}',now(),now());
insert into public.organizations(id,legal_name) values('aa000000-0000-0000-0000-000000000010','PVA A'),('bb000000-0000-0000-0000-000000000020','PVA B');
select private.seed_default_roles('aa000000-0000-0000-0000-000000000010','aa000000-0000-0000-0000-000000000001');select private.seed_default_roles('bb000000-0000-0000-0000-000000000020','bb000000-0000-0000-0000-000000000001');
insert into public.memberships(organization_id,user_id,role_id) select 'aa000000-0000-0000-0000-000000000010','aa000000-0000-0000-0000-000000000002',id from public.roles where organization_id='aa000000-0000-0000-0000-000000000010' and name='Somente leitura';
insert into public.farms(id,organization_id,name) values('aa000000-0000-0000-0000-000000000101','aa000000-0000-0000-0000-000000000010','A1'),('aa000000-0000-0000-0000-000000000102','aa000000-0000-0000-0000-000000000010','A2'),('bb000000-0000-0000-0000-000000000101','bb000000-0000-0000-0000-000000000020','B1');
insert into public.crop_seasons(id,organization_id,name,season_type,starts_on,ends_on) values
('aa000000-0000-0000-0000-000000000201','aa000000-0000-0000-0000-000000000010','Safra 2026/27','PRINCIPAL','2026-09-01','2027-08-31'),
('aa000000-0000-0000-0000-000000000202','aa000000-0000-0000-0000-000000000010','Safrinha 2027','SAFRINHA','2027-01-01','2027-08-31'),
('bb000000-0000-0000-0000-000000000201','bb000000-0000-0000-0000-000000000020','Safra B','PRINCIPAL','2026-09-01','2027-08-31');

set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','aa000000-0000-0000-0000-000000000001',true);
select public.apply_chart_account_template('aa000000-0000-0000-0000-000000000010','3269e51b-12de-5887-a85c-4461af91b4e9');
select public.apply_reporting_template('aa000000-0000-0000-0000-000000000010',id) from public.reporting_templates;
create temporary table fixture(version_id uuid,account_id uuid);
insert into fixture select public.create_budget_plan('aa000000-0000-0000-0000-000000000010','Orçamento 2027','2027-01-01','2027-12-01','aa000000-0000-0000-0000-000000000201','V1'),id from public.chart_accounts where organization_id='aa000000-0000-0000-0000-000000000010' and code='FINAGRO-V1-G020-S001';
select public.replace_budget_projection_items('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE',jsonb_build_array(jsonb_build_object('period_month','2027-01-01','chart_account_id',(select account_id from fixture),'crop_season_id','aa000000-0000-0000-0000-000000000201','farm_id','aa000000-0000-0000-0000-000000000101','amount','100.00'),jsonb_build_object('period_month','2027-02-01','chart_account_id',(select account_id from fixture),'crop_season_id','aa000000-0000-0000-0000-000000000201','farm_id','aa000000-0000-0000-0000-000000000101','amount','20.00')));
select public.replace_budget_projection_items('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DFC',jsonb_build_array(jsonb_build_object('period_month','2027-02-01','chart_account_id',(select account_id from fixture),'crop_season_id','aa000000-0000-0000-0000-000000000201','farm_id','aa000000-0000-0000-0000-000000000101','amount','50.00')));
select public.publish_budget_version('aa000000-0000-0000-0000-000000000010',(select version_id from fixture));
alter table fixture add column draft_version_id uuid;
update fixture set draft_version_id=public.copy_budget_version('aa000000-0000-0000-0000-000000000010',version_id,'Rascunho não oficial');
reset role;
insert into public.financial_entries(id,organization_id,entry_direction,status,issue_date,due_date,description,chart_account_id,crop_season_id,amount) values
('aa000000-0000-0000-0000-000000001001','aa000000-0000-0000-0000-000000000010','ENTRADA','PENDENTE','2027-01-10','2027-02-10','Realizado',(select account_id from fixture),'aa000000-0000-0000-0000-000000000201',125),
('aa000000-0000-0000-0000-000000001002','aa000000-0000-0000-0000-000000000010','ENTRADA','AGENDADO','2027-03-10','2027-03-10','Sem projeção',(select account_id from fixture),'aa000000-0000-0000-0000-000000000201',10);
insert into public.entry_allocations(organization_id,financial_entry_id,farm_id,percentage,allocated_amount) values
('aa000000-0000-0000-0000-000000000010','aa000000-0000-0000-0000-000000001001','aa000000-0000-0000-0000-000000000101',100,125),
('aa000000-0000-0000-0000-000000000010','aa000000-0000-0000-0000-000000001002','aa000000-0000-0000-0000-000000000101',100,10);

set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','aa000000-0000-0000-0000-000000000001',true);
create temporary table r as select public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE_COMPETENCIA','2027-01-01','2027-03-01') j;
select test_pva.ok(test_pva.metric((select j from r),'DRE.FINAGRO-V1-G020-S001','2027-01-01','projected')=100 and test_pva.metric((select j from r),'DRE.FINAGRO-V1-G020-S001','2027-01-01','actual')=125,'selected published DRE projection compares to issue-date actual');
select test_pva.ok(test_pva.metric((select j from r),'DRE.FINAGRO-V1-G020-S001','2027-01-01','variance_amount')=25 and test_pva.metric((select j from r),'DRE.FINAGRO-V1-G020-S001','2027-01-01','variance_percent')=25,'absolute and percentage variance are exact');
select test_pva.ok(test_pva.metric((select j from r),'DRE.FINAGRO-V1-G020-S001','2027-02-01','variance_percent')=-100,'projected-only value remains visible and produces minus one hundred percent');
select test_pva.ok(test_pva.metric((select j from r),'DRE.FINAGRO-V1-G002-S001','2027-02-01','variance_percent')=0,'zero projected and zero actual produce zero percent');
select test_pva.ok((select x->'values'->'2027-03-01'->>'variance_percent' is null and x->'values'->'2027-03-01'->>'warning'='Realizado sem valor projetado' from r cross join lateral jsonb_array_elements(j->'lines') x where x->>'code'='DRE.FINAGRO-V1-G020-S001'),'actual-only value remains visible with N/A warning');
select test_pva.ok(test_pva.metric(public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DFC_VENCIMENTO','2027-01-01','2027-03-01'),'DFC_PREVISTO.FINAGRO-V1-G020-S001','2027-02-01','actual')=125,'DFC actual uses due date and remains distinct from DRE');
select test_pva.ok(exists(select 1 from r cross join lateral jsonb_array_elements(j->'lines') x where x->>'line_type'='CALCULATED'),'calculated report lines are compared without becoming accounts');
select test_pva.ok((select x->'total'->>'aggregation' from jsonb_array_elements(public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DFC_VENCIMENTO','2027-01-01','2027-03-01')->'lines') x where x->>'code'='DFC_PREVISTO.CALC.SALDO_CAIXA_ACUMULADO')='LAST','DFC closing balance total is the last month rather than a monthly sum');
select test_pva.ok((public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE_SAFRA',null,null,null,'aa000000-0000-0000-0000-000000000201','aa000000-0000-0000-0000-000000000202')->>'comparison_view')='DRE_SAFRA','DRE Safra is an explicit independent view with seasons');
select test_pva.ok(position('account.name' in pg_get_functiondef('public.get_projected_vs_actual(uuid,uuid,text,date,date,uuid,uuid,uuid,uuid,uuid)'::regprocedure))=0 and position('source_name' in pg_get_functiondef('public.get_projected_vs_actual(uuid,uuid,text,date,date,uuid,uuid,uuid,uuid,uuid)'::regprocedure))=0 and position('settlements' in pg_get_functiondef('public.get_projected_vs_actual(uuid,uuid,text,date,date,uuid,uuid,uuid,uuid,uuid)'::regprocedure))=0,'engine is independent of names and settlements');
select test_pva.err($$select public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE_COMPETENCIA','2027-01-01','2027-03-01','bb000000-0000-0000-0000-000000000101')$$,'FARM_NOT_FOUND_IN_ORGANIZATION');
select test_pva.err($$select public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select draft_version_id from fixture),'DRE_COMPETENCIA','2027-01-01','2027-03-01')$$,'PUBLISHED_BUDGET_VERSION_NOT_FOUND');
select test_pva.err($$select public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010','bb000000-0000-0000-0000-000000000777','DRE_COMPETENCIA','2027-01-01','2027-03-01')$$,'PUBLISHED_BUDGET_VERSION_NOT_FOUND');
select test_pva.err($$select public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE_SAFRA',null,null,null,'bb000000-0000-0000-0000-000000000201','aa000000-0000-0000-0000-000000000202')$$,'PRIMARY_CROP_SEASON_INVALID');
select test_pva.err($$select public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE_SAFRA',null,null,null,'aa000000-0000-0000-0000-000000000201','bb000000-0000-0000-0000-000000000201')$$,'SECOND_CROP_SEASON_INVALID');
select test_pva.err($$select public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE_COMPETENCIA','2027-01-01','2027-03-01',null,null,null,'bb000000-0000-0000-0000-000000000999')$$,'PROJECTION_STRUCTURE_NOT_FOUND');
select test_pva.err($$select public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE_COMPETENCIA','2027-01-01','2027-03-01',null,null,null,null,'bb000000-0000-0000-0000-000000000999')$$,'DRE_STRUCTURE_NOT_FOUND');
select set_config('request.jwt.claim.sub','aa000000-0000-0000-0000-000000000002',true);select test_pva.ok((public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE_COMPETENCIA','2027-01-01','2027-03-01')->>'comparison_view')='DRE_COMPETENCIA','READ_ONLY can compare');
select set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000001',true);select test_pva.err($$select public.get_projected_vs_actual('aa000000-0000-0000-0000-000000000010',(select version_id from fixture),'DRE_COMPETENCIA','2027-01-01','2027-03-01')$$,'PERMISSION_DENIED');
select test_pva.err($$select public.get_projected_vs_actual('bb000000-0000-0000-0000-000000000020',(select version_id from fixture),'DRE_COMPETENCIA','2027-01-01','2027-03-01')$$,'PUBLISHED_BUDGET_VERSION_NOT_FOUND');
rollback;
