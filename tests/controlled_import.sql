-- Controlled FINAGRO import: dry-run, tenant isolation, idempotency and rollback.
begin;
create schema test_import;
create function test_import.ok(v boolean,m text) returns void language plpgsql set search_path='' as $$begin if v is not true then raise exception 'TEST FAILED: %',m;end if;end$$;
create function test_import.fails(sql text,fragment text) returns void language plpgsql set search_path='' as $$declare m text;begin begin execute sql;exception when others then m=sqlerrm;if position(fragment in m)=0 then raise exception 'TEST FAILED: expected %, got %',fragment,m;end if;return;end;raise exception 'TEST FAILED: expected error %',fragment;end$$;
grant usage on schema test_import to authenticated;grant execute on all functions in schema test_import to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('97000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','import-a@test.local','x',now(),'{}','{}',now(),now()),
('98000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','import-b@test.local','x',now(),'{}','{}',now(),now());
insert into public.organizations(id,legal_name) values('97000000-0000-0000-0000-000000000010','Import A'),('98000000-0000-0000-0000-000000000020','Import B');
select private.seed_default_roles('97000000-0000-0000-0000-000000000010','97000000-0000-0000-0000-000000000001');select private.seed_default_roles('98000000-0000-0000-0000-000000000020','98000000-0000-0000-0000-000000000002');
insert into public.farms(id,organization_id,name) values('97000000-0000-0000-0000-000000000101','97000000-0000-0000-0000-000000000010','HS'),('98000000-0000-0000-0000-000000000102','98000000-0000-0000-0000-000000000020','Fazenda B');
insert into public.crop_seasons(id,organization_id,name,season_type) values('97000000-0000-0000-0000-000000000201','97000000-0000-0000-0000-000000000010','2027/28','PRINCIPAL');
insert into public.chart_accounts(id,organization_id,code,name,source_name,managerial_type,nature,allows_allocation) values('97000000-0000-0000-0000-000000000301','97000000-0000-0000-0000-000000000010','G','Grupo','Grupo_Fonte','OUTRO','NEUTRA',true);
insert into public.chart_accounts(id,organization_id,code,name,source_name,parent_id,level,managerial_type,nature,allows_allocation) values('97000000-0000-0000-0000-000000000302','97000000-0000-0000-0000-000000000010','G.1','Filha','Filha Fonte','97000000-0000-0000-0000-000000000301',2,'OUTRO','NEUTRA',true);

select test_import.ok(to_regprocedure('public.analyze_finagro_import(uuid,text,text,date,date,jsonb)') is not null,'analysis RPC exists');
select test_import.fails($$select public.analyze_finagro_import('97000000-0000-0000-0000-000000000010','a.xlsx','anon','2027-01-01','2027-01-31','[]')$$,'PERMISSION_DENIED');
set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000001',true);

select public.analyze_finagro_import('97000000-0000-0000-0000-000000000010','blocked.xlsx','blocked-hash','2027-01-01','2027-01-31',jsonb_build_array(
 jsonb_build_object('source_row_number',7,'issue_date','2027-01-10','due_date','2027-02-10','group','Grupo_Fonte','subgroup','Filha Fonte','description','Pago histórico','amount','100.01','status','PAGO','direction','S','farm','HS','season','2027/28'),
 jsonb_build_object('source_row_number',8,'issue_date','2027-01-11','due_date','2027-02-11','group','Grupo_Fonte','subgroup','Filha Fonte','description','Geral','amount','200','status','PENDENTE','direction','E','farm','GERAL','season','2027/28'),
 jsonb_build_object('source_row_number',9,'issue_date','2027-01-12','due_date','2027-02-12','group','Grupo_Fonte','subgroup','Filha Fonte','description','Inválido','amount','-1','status','NOVO','direction','X','farm','HS','season','2027/28')));
select test_import.ok((select blocked_rows=3 and is_dry_run and status='ANALISADO' from public.import_batches where source_file_sha256='blocked-hash'),'dry-run classifies blocking rows');
select test_import.ok((select count(*)=0 from public.financial_entries),'analysis never creates financial entries');
select test_import.ok((select count(*)=1 from public.import_staging_rows r, jsonb_array_elements(r.issues) i where i->>'code'='PAID_SETTLEMENT_POLICY_REQUIRED'),'PAGO requires explicit human settlement policy');
select test_import.ok((select count(*)=1 from public.import_staging_rows r, jsonb_array_elements(r.issues) i where i->>'code'='GENERAL_REQUIRES_ALLOCATION_RULE'),'GERAL never becomes a farm');
select test_import.fails($$select public.confirm_finagro_import('97000000-0000-0000-0000-000000000010',(select id from public.import_batches where source_file_sha256='blocked-hash'))$$,'IMPORT_BATCH_NOT_READY');
select test_import.fails($$select public.analyze_finagro_import('97000000-0000-0000-0000-000000000010','blocked.xlsx','blocked-hash','2027-01-01','2027-01-31','[]')$$,'duplicate key');
select test_import.fails($$select public.save_import_mapping('97000000-0000-0000-0000-000000000010','FARM','B','', '98000000-0000-0000-0000-000000000102',null)$$,'NOT_FOUND_IN_ORGANIZATION');

select public.analyze_finagro_import('97000000-0000-0000-0000-000000000010','valid.xlsx','valid-hash','2027-01-01','2027-01-31',jsonb_build_array(jsonb_build_object('source_row_number',7,'issue_date','2027-01-10','due_date','2027-02-10','group','Grupo_Fonte','subgroup','Filha Fonte','description','Importável','amount','100.01','status','PENDENTE','direction','S','farm','HS','season','2027/28')));
select test_import.ok((select valid_rows=1 and blocked_rows=0 from public.import_batches where source_file_sha256='valid-hash'),'exact group/subgroup farm and season resolve');
select public.confirm_finagro_import('97000000-0000-0000-0000-000000000010',(select id from public.import_batches where source_file_sha256='valid-hash'));
select test_import.ok((select count(*)=1 from public.financial_entries where source_type='IMPORTACAO' and amount=100.01),'confirmation creates one exact NUMERIC entry');
select test_import.ok((select count(*)=1 and sum(percentage)=100 and sum(allocated_amount)=100.01 from public.entry_allocations),'direct allocation is exact and snapshot based');
select test_import.ok((select count(*)=0 from public.import_batches where organization_id='98000000-0000-0000-0000-000000000020'),'A cannot read B batches');
select test_import.fails($$select public.rollback_finagro_import('98000000-0000-0000-0000-000000000020',(select id from public.import_batches where source_file_sha256='valid-hash'))$$,'PERMISSION_DENIED');
select public.rollback_finagro_import('97000000-0000-0000-0000-000000000010',(select id from public.import_batches where source_file_sha256='valid-hash'));
reset role;
select test_import.ok((select status='REVERTIDO' from public.import_batches where source_file_sha256='valid-hash'),'batch rollback is traceable');
select test_import.ok((select deleted_at is not null from public.financial_entries where source_type='IMPORTACAO'),'rollback only soft deletes imported entry');
select test_import.ok((select count(*)>=3 from public.audit_logs where entity_type='IMPORT_BATCH'),'analyze confirm and rollback are audited');
rollback;
