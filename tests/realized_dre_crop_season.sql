-- FINAGRO Web — DRE Safra: seasonal configuration, temporal cycle and tenant safety.
begin;
create schema test_ds;
create function test_ds.ok(c boolean,m text) returns void language plpgsql set search_path='' as $$begin if c is not true then raise exception 'TEST FAILED: %',m;end if;end$$;
create function test_ds.err(q text,e text) returns void language plpgsql set search_path='' as $$declare m text;begin begin execute q;exception when others then m=sqlerrm;if position(e in m)=0 then raise exception 'TEST FAILED expected %, got %',e,m;end if;return;end;raise exception 'TEST FAILED expected %',e;end$$;
create function test_ds.value_at(j jsonb,c text,m text) returns numeric language sql immutable set search_path='' as $$select coalesce((x->'values'->>$3)::numeric,0) from jsonb_array_elements($1->'lines') x where x->>'code'=$2$$;
grant usage on schema test_ds to authenticated;grant execute on all functions in schema test_ds to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('c1000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-owner@example.test','x',now(),'{}','{}',now(),now()),
('c1000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-read@example.test','x',now(),'{}','{}',now(),now()),
('d1000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ds-other@example.test','x',now(),'{}','{}',now(),now());
insert into public.organizations(id,legal_name) values('c1000000-0000-0000-0000-000000000010','Safra A'),('d1000000-0000-0000-0000-000000000020','Safra B');
select private.seed_default_roles('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000001');select private.seed_default_roles('d1000000-0000-0000-0000-000000000020','d1000000-0000-0000-0000-000000000001');
insert into public.memberships(organization_id,user_id,role_id) select 'c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000002',id from public.roles where organization_id='c1000000-0000-0000-0000-000000000010' and name='Somente leitura';
insert into public.farms(id,organization_id,name) values('c1000000-0000-0000-0000-000000000101','c1000000-0000-0000-0000-000000000010','A1'),('c1000000-0000-0000-0000-000000000102','c1000000-0000-0000-0000-000000000010','A2'),('d1000000-0000-0000-0000-000000000101','d1000000-0000-0000-0000-000000000020','B1');
insert into public.crop_seasons(id,organization_id,name,season_type,starts_on,ends_on) values
('c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000010','Safra 2026/27','PRINCIPAL','2026-09-01','2027-08-31'),
('c1000000-0000-0000-0000-000000000202','c1000000-0000-0000-0000-000000000010','Safrinha 2027','SAFRINHA','2027-01-01','2027-08-31'),
('c1000000-0000-0000-0000-000000000203','c1000000-0000-0000-0000-000000000010','Outra','OUTRA','2026-09-01','2027-08-31'),
('d1000000-0000-0000-0000-000000000201','d1000000-0000-0000-0000-000000000020','Safra B','PRINCIPAL','2026-09-01','2027-08-31'),
('d1000000-0000-0000-0000-000000000202','d1000000-0000-0000-0000-000000000020','Safrinha B','SAFRINHA','2027-01-01','2027-08-31');
insert into public.allocation_rules(id,organization_id,crop_season_id,name,is_active) values('c1000000-0000-0000-0000-000000000301','c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000202','Rateio 45/55',true);
insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage) values('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000301','c1000000-0000-0000-0000-000000000101',45),('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000301','c1000000-0000-0000-0000-000000000102',55);

set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000001',true);
select public.apply_chart_account_template('c1000000-0000-0000-0000-000000000010','3269e51b-12de-5887-a85c-4461af91b4e9');
select public.apply_reporting_template('c1000000-0000-0000-0000-000000000010','354d5bb6-7376-5daa-b2fa-c2871da2a9ac');
reset role;
select test_ds.ok((select count(*)=4 from public.report_season_rule_templates),'exactly four approved FINAGRO seasonal accounts are configured by template IDs');
select test_ds.ok((select count(*)=4 from public.report_season_rules where organization_id='c1000000-0000-0000-0000-000000000010'),'organization received independent seasonal rules');
select test_ds.ok(not exists(select 1 from public.report_season_rule_templates r join public.chart_account_template_items a on a.id=r.chart_template_item_id where a.name not in ('Adubo','Fretes sobre Matéria Prima','Produtos Quimicos','Sementes')),'season rules use IDs and only approved mappings');
select test_ds.ok((select count(*)=4 from public.report_account_template_mappings m join public.reporting_templates t on t.id=m.reporting_template_id where t.code='DRE_SAFRA' and m.season_behavior='SEASONAL'),'Adubo, Fretes, Produtos Quimicos and Sementes remain the only explicit seasonal template mappings');
select test_ds.ok((select count(*)=2 from public.report_account_template_mappings m join public.reporting_templates t on t.id=m.reporting_template_id join public.chart_account_template_items a on a.id=m.chart_template_item_id where t.code='DRE_SAFRA' and a.code in ('FINAGRO-V1-G002-S002','FINAGRO-V1-G002-S004') and m.season_behavior='REGULAR' and m.crop_filter_mode='NONE'),'Calcario and Gesso are explicit regular template mappings');

create temporary table ac as select code,id from public.chart_accounts where organization_id='c1000000-0000-0000-0000-000000000010';
update public.chart_accounts set allows_allocation=true where id=(select id from ac where code='FINAGRO-V1-G002-S001');
insert into public.chart_accounts(id,organization_id,code,name,managerial_type,nature) values('c1000000-0000-0000-0000-000000000999','c1000000-0000-0000-0000-000000000010','DS-SEM-MAP','Nome irrelevante','OUTRO','NEUTRA');
insert into public.bank_accounts(id,organization_id,bank_name,account_number) values('c1000000-0000-0000-0000-000000000401','c1000000-0000-0000-0000-000000000010','Teste','1');
insert into public.financial_entries(id,organization_id,entry_direction,status,issue_date,due_date,description,chart_account_id,crop_season_id,amount) values
('c1000000-0000-0000-0000-000000001001','c1000000-0000-0000-0000-000000000010','SAIDA','PENDENTE','2025-09-10','2028-01-01','prior seasonal',(select id from ac where code='FINAGRO-V1-G002-S001'),'c1000000-0000-0000-0000-000000000201',10.01),
('c1000000-0000-0000-0000-000000001002','c1000000-0000-0000-0000-000000000010','SAIDA','AGENDADO','2026-09-10','2029-01-01','current seasonal',(select id from ac where code='FINAGRO-V1-G002-S001'),'c1000000-0000-0000-0000-000000000202',20.02),
('c1000000-0000-0000-0000-000000001003','c1000000-0000-0000-0000-000000000010','SAIDA','PENDENTE','2026-09-11','2026-09-11','wrong season',(select id from ac where code='FINAGRO-V1-G002-S001'),'c1000000-0000-0000-0000-000000000203',99),
('c1000000-0000-0000-0000-000000001004','c1000000-0000-0000-0000-000000000010','ENTRADA','PENDENTE','2026-09-12','2030-01-01','regular ignores crop',(select id from ac where code='FINAGRO-V1-G020-S001'),'c1000000-0000-0000-0000-000000000203',100),
('c1000000-0000-0000-0000-000000001005','c1000000-0000-0000-0000-000000000010','SAIDA','PENDENTE','2026-09-13','2031-01-01','lime current other season',(select id from ac where code='FINAGRO-V1-G002-S002'),'c1000000-0000-0000-0000-000000000203',7),
('c1000000-0000-0000-0000-000000001006','c1000000-0000-0000-0000-000000000010','ENTRADA','PENDENTE','2026-10-01','2026-10-01','unmapped','c1000000-0000-0000-0000-000000000999',null,3.33),
('c1000000-0000-0000-0000-000000001007','c1000000-0000-0000-0000-000000000010','SAIDA','AGENDADO','2026-09-14','2032-01-01','lime current no season',(select id from ac where code='FINAGRO-V1-G002-S002'),null,2),
('c1000000-0000-0000-0000-000000001008','c1000000-0000-0000-0000-000000000010','SAIDA','PENDENTE','2025-09-14','2026-09-14','lime prior must not combine',(select id from ac where code='FINAGRO-V1-G002-S002'),'c1000000-0000-0000-0000-000000000201',70),
('c1000000-0000-0000-0000-000000001009','c1000000-0000-0000-0000-000000000010','SAIDA','PENDENTE','2026-09-15','2033-01-01','gypsum current other season',(select id from ac where code='FINAGRO-V1-G002-S004'),'c1000000-0000-0000-0000-000000000203',8),
('c1000000-0000-0000-0000-000000001010','c1000000-0000-0000-0000-000000000010','SAIDA','AGENDADO','2026-09-16','2034-01-01','gypsum current no season',(select id from ac where code='FINAGRO-V1-G002-S004'),null,3),
('c1000000-0000-0000-0000-000000001011','c1000000-0000-0000-0000-000000000010','SAIDA','PENDENTE','2025-09-16','2026-09-16','gypsum prior must not combine',(select id from ac where code='FINAGRO-V1-G002-S004'),'c1000000-0000-0000-0000-000000000202',80);
insert into public.entry_allocations(organization_id,financial_entry_id,farm_id,allocation_rule_id,percentage,allocated_amount,snapshot_rule_name,snapshot_crop_season_name) values
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001001','c1000000-0000-0000-0000-000000000101',null,100,10.01,null,null),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001002','c1000000-0000-0000-0000-000000000101','c1000000-0000-0000-0000-000000000301',45,9.01,'Rateio 45/55','Safrinha 2027'),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001002','c1000000-0000-0000-0000-000000000102','c1000000-0000-0000-0000-000000000301',55,11.01,'Rateio 45/55','Safrinha 2027'),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001003','c1000000-0000-0000-0000-000000000101',null,100,99,null,null),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001004','c1000000-0000-0000-0000-000000000101',null,100,100,null,null),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001005','c1000000-0000-0000-0000-000000000101',null,100,7,null,null),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001006','c1000000-0000-0000-0000-000000000101',null,100,3.33,null,null),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001007','c1000000-0000-0000-0000-000000000102',null,100,2,null,null),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001008','c1000000-0000-0000-0000-000000000101',null,100,70,null,null),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001009','c1000000-0000-0000-0000-000000000101',null,100,8,null,null),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001010','c1000000-0000-0000-0000-000000000102',null,100,3,null,null),
('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001011','c1000000-0000-0000-0000-000000000101',null,100,80,null,null);
insert into public.settlements(organization_id,financial_entry_id,bank_account_id,settled_at,amount) values('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000001001','c1000000-0000-0000-0000-000000000401','2030-12-31',10.01);
update public.financial_entries set status='PAGO' where id='c1000000-0000-0000-0000-000000001001';
update public.allocation_rule_items set percentage=50 where allocation_rule_id='c1000000-0000-0000-0000-000000000301';
set constraints all immediate;set constraints all deferred;

set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000001',true);
create temporary table result as select public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202') j;
select test_ds.ok((select j->'months'->>0='2026-09-01' and j->'months'->>11='2027-08-01' from result),'cycle crosses calendar years using structured season dates');
select test_ds.ok(test_ds.value_at((select j from result),'DRE_SAFRA.FINAGRO-V1-G002-S001','2026-09-01')=30.03,'seasonal line combines selected seasons current and prior-year month with exact numeric cents');
select test_ds.ok(test_ds.value_at((select j from result),'DRE_SAFRA.FINAGRO-V1-G020-S001','2026-09-01')=100,'regular line does not receive a global crop-season filter');
select test_ds.ok(test_ds.value_at((select j from result),'DRE_SAFRA.FINAGRO-V1-G002-S002','2026-09-01')=9,'Calcario uses issue date, ignores crop season and does not combine prior-year month');
select test_ds.ok(test_ds.value_at((select j from result),'DRE_SAFRA.FINAGRO-V1-G002-S004','2026-09-01')=11,'Gesso uses issue date, ignores crop season and does not combine prior-year month');
select test_ds.ok(test_ds.value_at((select j from result),'DRE_SAFRA.CALC.RECEITA_OPERACIONAL_BRUTA','2026-09-01')=100 and test_ds.value_at((select j from result),'DRE_SAFRA.CALC.LUCRO_BRUTO','2026-09-01')=49.97,'calculated lines reconcile without parent-child double counting');
select test_ds.ok(jsonb_array_length((select j->'coverage'->'seasonal_config_missing' from result))=0,'Calcario and Gesso do not raise missing seasonal configuration alerts');
select test_ds.ok(((select j from result)->'coverage'->>'entries_unmapped')::int=1 and ((select j from result)->'coverage'->>'unclassified_amount')::numeric=3.33,'unmapped account is visible with exact amount');
select test_ds.ok(test_ds.value_at(public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202','c1000000-0000-0000-0000-000000000101'),'DRE_SAFRA.FINAGRO-V1-G002-S001','2026-09-01')=19.02,'farm view uses stored allocations');
select test_ds.ok(test_ds.value_at(public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202','c1000000-0000-0000-0000-000000000101'),'DRE_SAFRA.FINAGRO-V1-G002-S001','2026-09-01')=19.02,'changing current allocation rule does not change snapshot history');
select test_ds.ok(test_ds.value_at(public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202','c1000000-0000-0000-0000-000000000101'),'DRE_SAFRA.FINAGRO-V1-G002-S001','2026-09-01')+test_ds.value_at(public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202','c1000000-0000-0000-0000-000000000102'),'DRE_SAFRA.FINAGRO-V1-G002-S001','2026-09-01')=30.03,'farms equal consolidated');
select test_ds.ok(test_ds.value_at(public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202','c1000000-0000-0000-0000-000000000101'),'DRE_SAFRA.FINAGRO-V1-G002-S002','2026-09-01')+test_ds.value_at(public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202','c1000000-0000-0000-0000-000000000102'),'DRE_SAFRA.FINAGRO-V1-G002-S002','2026-09-01')=9,'Calcario consolidated equals farms');
select test_ds.ok(test_ds.value_at(public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202','c1000000-0000-0000-0000-000000000101'),'DRE_SAFRA.FINAGRO-V1-G002-S004','2026-09-01')+test_ds.value_at(public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202','c1000000-0000-0000-0000-000000000102'),'DRE_SAFRA.FINAGRO-V1-G002-S004','2026-09-01')=11,'Gesso consolidated equals farms');
select test_ds.err($$select public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','d1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202')$$,'PRIMARY_CROP_SEASON_INVALID');
select test_ds.err($$select public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','d1000000-0000-0000-0000-000000000202')$$,'SECOND_CROP_SEASON_INVALID');
select test_ds.err($$select public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202','d1000000-0000-0000-0000-000000000101')$$,'FARM_NOT_FOUND_IN_ORGANIZATION');
select test_ds.err($$select public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202',null,'d1000000-0000-0000-0000-000000000999')$$,'DRE_CROP_SEASON_STRUCTURE_NOT_FOUND');
select test_ds.ok(position('Adubo' in pg_get_functiondef('public.get_realized_dre_crop_season(uuid,uuid,uuid,uuid,uuid)'::regprocedure))=0 and position('source_name' in pg_get_functiondef('public.get_realized_dre_crop_season(uuid,uuid,uuid,uuid,uuid)'::regprocedure))=0,'engine does not depend on account display/source names');
select test_ds.ok(position('45/15/40' in pg_get_functiondef('public.get_realized_dre_crop_season(uuid,uuid,uuid,uuid,uuid)'::regprocedure))=0 and position('70%' in pg_get_functiondef('public.get_realized_dre_crop_season(uuid,uuid,uuid,uuid,uuid)'::regprocedure))=0,'historical fixed percentages are absent from engine');
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000002',true);select test_ds.ok((public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202')->>'structure_id') is not null,'READ_ONLY can query');
select set_config('request.jwt.claim.sub','d1000000-0000-0000-0000-000000000001',true);
select public.apply_chart_account_template('d1000000-0000-0000-0000-000000000020','3269e51b-12de-5887-a85c-4461af91b4e9');select public.apply_reporting_template('d1000000-0000-0000-0000-000000000020','354d5bb6-7376-5daa-b2fa-c2871da2a9ac');
update public.report_season_rules set prior_month_offset=11 where id=(select id from public.report_season_rules where organization_id='d1000000-0000-0000-0000-000000000020' order by id limit 1);
select test_ds.err($$select public.get_realized_dre_crop_season('c1000000-0000-0000-0000-000000000010','c1000000-0000-0000-0000-000000000201','c1000000-0000-0000-0000-000000000202')$$,'PERMISSION_DENIED');
reset role;
select test_ds.ok((select count(*)=4 and min(prior_month_offset)=12 and max(prior_month_offset)=12 from public.report_season_rules where organization_id='c1000000-0000-0000-0000-000000000010'),'organization B customization does not alter organization A');
select test_ds.ok((select min(prior_month_offset)=12 and max(prior_month_offset)=12 from public.report_season_rule_templates),'organization customization does not alter template');
rollback;
