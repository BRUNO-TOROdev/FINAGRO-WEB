-- GENERAL allocation and operation producer integration tests (synthetic only).
begin;
create schema test_general;
create function test_general.ok(v boolean,m text)returns void language plpgsql set search_path='' as $$begin if v is not true then raise exception 'TEST FAILED: %',m;end if;end$$;
create function test_general.fails(sql text,fragment text)returns void language plpgsql set search_path='' as $$declare m text;begin begin execute sql;set constraints all immediate;exception when others then m=sqlerrm;set constraints all deferred;if position(fragment in m)=0 then raise exception 'TEST FAILED: expected %, got %',fragment,m;end if;return;end;raise exception 'TEST FAILED: expected error %',fragment;end$$;
grant usage on schema test_general to authenticated;grant execute on all functions in schema test_general to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)values
('aa000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','general-a@test.local','x',now(),'{}','{}',now(),now()),
('aa000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','general-reader@test.local','x',now(),'{}','{}',now(),now()),
('bb000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','general-b@test.local','x',now(),'{}','{}',now(),now());
insert into public.organizations(id,legal_name)values('aa000000-0000-0000-0000-000000000010','Tenant A'),('bb000000-0000-0000-0000-000000000020','Tenant B');
select private.seed_default_roles('aa000000-0000-0000-0000-000000000010','aa000000-0000-0000-0000-000000000001');select private.seed_default_roles('bb000000-0000-0000-0000-000000000020','bb000000-0000-0000-0000-000000000002');
insert into public.memberships(organization_id,user_id,role_id)select 'aa000000-0000-0000-0000-000000000010','aa000000-0000-0000-0000-000000000003',id from public.roles where organization_id='aa000000-0000-0000-0000-000000000010' and name='Somente leitura';
insert into public.farms(id,organization_id,name)values
('aa000000-0000-0000-0000-000000000101','aa000000-0000-0000-0000-000000000010','Fazenda A'),
('aa000000-0000-0000-0000-000000000102','aa000000-0000-0000-0000-000000000010','Fazenda B'),
('aa000000-0000-0000-0000-000000000103','aa000000-0000-0000-0000-000000000010','Fazenda C'),
('bb000000-0000-0000-0000-000000000104','bb000000-0000-0000-0000-000000000020','Fazenda X');
insert into public.crop_seasons(id,organization_id,name,season_type)values('aa000000-0000-0000-0000-000000000201','aa000000-0000-0000-0000-000000000010','Safra A','PRINCIPAL');
insert into public.chart_accounts(id,organization_id,code,name,source_name,managerial_type,nature,allows_allocation)values('aa000000-0000-0000-0000-000000000301','aa000000-0000-0000-0000-000000000010','1','Grupo','Grupo','OUTRO','NEUTRA',true);
insert into public.chart_accounts(id,organization_id,code,name,source_name,parent_id,managerial_type,nature,allows_allocation)values('aa000000-0000-0000-0000-000000000302','aa000000-0000-0000-0000-000000000010','1.1','Conta','Conta','aa000000-0000-0000-0000-000000000301','OUTRO','NEUTRA',true);
insert into public.parties(id,organization_id,name,party_type)values('aa000000-0000-0000-0000-000000000401','aa000000-0000-0000-0000-000000000010','Empresa Externa A','AMBOS'),('aa000000-0000-0000-0000-000000000402','aa000000-0000-0000-0000-000000000010','Empresa Externa B','AMBOS');
insert into public.operation_producers(id,organization_id,name)values('aa000000-0000-0000-0000-000000000501','aa000000-0000-0000-0000-000000000010','Produtor A'),('aa000000-0000-0000-0000-000000000502','aa000000-0000-0000-0000-000000000010','Produtor B'),('bb000000-0000-0000-0000-000000000503','bb000000-0000-0000-0000-000000000020','Produtor X');
insert into public.bank_accounts(id,organization_id,bank_name,account_number)values('aa000000-0000-0000-0000-000000000601','aa000000-0000-0000-0000-000000000010','Banco Teste','0001'),('bb000000-0000-0000-0000-000000000602','bb000000-0000-0000-0000-000000000020','Banco X','0002');

set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','aa000000-0000-0000-0000-000000000001',true);
select public.save_general_allocation_rule('aa000000-0000-0000-0000-000000000010',null,'Geral piloto',null,true,'2026-01-01','2026-01-31','[{"farm_id":"aa000000-0000-0000-0000-000000000101","percentage":"45"},{"farm_id":"aa000000-0000-0000-0000-000000000102","percentage":"15"},{"farm_id":"aa000000-0000-0000-0000-000000000103","percentage":"40"}]');
select test_general.ok((select allocation_scope='GENERAL' and crop_season_id is null and effective_from='2026-01-01' from public.allocation_rules where name='Geral piloto'),'GENERAL has null season and explicit validity');
select test_general.ok(public.resolve_general_allocation_rule('aa000000-0000-0000-0000-000000000010','2026-01-15')=(select id from public.allocation_rules where name='Geral piloto'),'January rule resolves by date');
select test_general.fails($$select public.resolve_general_allocation_rule('aa000000-0000-0000-0000-000000000010','2026-02-01')$$,'NOT_FOUND_FOR_DATE');
select test_general.fails($$select public.save_general_allocation_rule('aa000000-0000-0000-0000-000000000010',null,'Sobreposta',null,true,'2026-01-15','2026-02-15','[{"farm_id":"aa000000-0000-0000-0000-000000000101","percentage":"100"}]')$$,'PERIOD_OVERLAP');
select test_general.fails($$select public.save_general_allocation_rule('aa000000-0000-0000-0000-000000000010',null,'Cross farm',null,false,'2027-01-01',null,'[{"farm_id":"bb000000-0000-0000-0000-000000000104","percentage":"100"}]')$$,'FARM_NOT_FOUND_IN_ORGANIZATION');
select public.save_general_allocation_rule('aa000000-0000-0000-0000-000000000010',(select id from public.allocation_rules where name='Geral piloto'),'Geral piloto','Edição do mesmo registro',true,'2026-01-01','2026-01-31','[{"farm_id":"aa000000-0000-0000-0000-000000000101","percentage":"45"},{"farm_id":"aa000000-0000-0000-0000-000000000102","percentage":"15"},{"farm_id":"aa000000-0000-0000-0000-000000000103","percentage":"40"}]');
select test_general.ok((select count(*)=1 and bool_and(description='Edição do mesmo registro') from public.allocation_rules where organization_id='aa000000-0000-0000-0000-000000000010' and name='Geral piloto'),'OWNER edits the same GENERAL rule without duplication');
select test_general.fails($$select public.save_general_allocation_rule('aa000000-0000-0000-0000-000000000010',(select id from public.allocation_rules where name='Geral piloto'),'Geral piloto',null,true,'2026-01-01','2026-01-31','[{"farm_id":"aa000000-0000-0000-0000-000000000101","percentage":"44"},{"farm_id":"aa000000-0000-0000-0000-000000000102","percentage":"15"},{"farm_id":"aa000000-0000-0000-0000-000000000103","percentage":"40"}]')$$,'MUST_TOTAL_100');
select set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000002',true);select test_general.fails($$select public.save_general_allocation_rule('aa000000-0000-0000-0000-000000000010',(select id from public.allocation_rules where name='Geral piloto'),'Cross tenant',null,true,'2026-01-01','2026-01-31','[{"farm_id":"aa000000-0000-0000-0000-000000000101","percentage":"100"}]')$$,'PERMISSION_DENIED');
select set_config('request.jwt.claim.sub','aa000000-0000-0000-0000-000000000003',true);select test_general.fails($$select public.save_general_allocation_rule('aa000000-0000-0000-0000-000000000010',(select id from public.allocation_rules where name='Geral piloto'),'Read only',null,true,'2026-01-01','2026-01-31','[{"farm_id":"aa000000-0000-0000-0000-000000000101","percentage":"100"}]')$$,'PERMISSION_DENIED');
select set_config('request.jwt.claim.sub','aa000000-0000-0000-0000-000000000001',true);

select public.save_import_mapping('aa000000-0000-0000-0000-000000000010','PARTY','Empresa Externa A','DOC-A','aa000000-0000-0000-0000-000000000401',null);
select public.save_import_mapping('aa000000-0000-0000-0000-000000000010','PARTY','Empresa Externa B','DOC-B','aa000000-0000-0000-0000-000000000402',null);
select public.save_import_mapping('aa000000-0000-0000-0000-000000000010','PRODUCER','Produtor A','','aa000000-0000-0000-0000-000000000501',null);
select public.save_import_mapping('aa000000-0000-0000-0000-000000000010','PRODUCER','Produtor B','','aa000000-0000-0000-0000-000000000502',null);
select public.save_import_mapping('aa000000-0000-0000-0000-000000000010','BANK_ACCOUNT','Banco Teste','0001','aa000000-0000-0000-0000-000000000601',null);
select test_general.fails($$select public.save_import_mapping('aa000000-0000-0000-0000-000000000010','PRODUCER','Cross','','bb000000-0000-0000-0000-000000000503',null)$$,'NOT_FOUND_IN_ORGANIZATION');
select test_general.fails($$select public.save_import_mapping('aa000000-0000-0000-0000-000000000010','BANK_ACCOUNT','Cross','','bb000000-0000-0000-0000-000000000602',null)$$,'NOT_FOUND_IN_ORGANIZATION');

select public.analyze_finagro_import('aa000000-0000-0000-0000-000000000010','synthetic.xlsx','synthetic-general','2026-01-01','2026-01-31',jsonb_build_array(
 jsonb_build_object('source_row_number',7,'issue_date','2026-01-10','due_date','2026-01-20','group','Grupo','subgroup','Conta','document_name','Empresa Externa A','client','DOC-A','producer','Produtor A','description','Entrada sintética','amount','100.01','status','PAGO','direction','E','farm','GERAL','bank','Banco Teste','bank_account','0001'),
 jsonb_build_object('source_row_number',8,'issue_date','2026-01-11','due_date','2026-01-21','group','Grupo','subgroup','Conta','document_name','Empresa Externa B','client','DOC-B','producer','Produtor A','description','Saída sintética','amount','10.00','status','PENDENTE','direction','S','farm','GERAL'),
 jsonb_build_object('source_row_number',9,'issue_date','2026-01-12','due_date','2026-01-22','group','Grupo','subgroup','Conta','document_name','Empresa Externa A','client','DOC-A','producer','Produtor B','description','Outra sintética','amount','20.00','status','PENDENTE','direction','S','farm','Fazenda A')));
select test_general.ok((select blocked_rows=0 and total_rows=3 from public.import_batches where source_file_sha256='synthetic-general'),'GERAL without season resolves and party/producer remain independent');
select test_general.ok((select count(*)=2 from public.import_staging_rows where allocation_rule_id is not null and crop_season_id is null),'GERAL rows use rule without season');
select public.confirm_finagro_import('aa000000-0000-0000-0000-000000000010',(select id from public.import_batches where source_file_sha256='synthetic-general'));
select test_general.ok((select count(distinct counterparty_id)=2 and count(distinct operation_producer_id)=2 from public.financial_entries where source_type='IMPORTACAO'),'counterparties and producers are distinct dimensions');
select test_general.ok((select count(*)=6 and sum(allocated_amount)=110.01 from public.entry_allocations a join public.financial_entries e on e.id=a.financial_entry_id where e.source_type='IMPORTACAO' and a.allocation_rule_id is not null),'GENERAL snapshots allocate 45/15/40 without duplicating value');
select test_general.ok((select count(*)=1 from public.settlements where date_basis='DUE_DATE_SURROGATE'),'PAGO GENERAL creates one surrogate settlement');
update public.allocation_rule_items set percentage=50 where allocation_rule_id=(select id from public.allocation_rules where name='Geral piloto')and farm_id='aa000000-0000-0000-0000-000000000101';
update public.allocation_rule_items set percentage=35 where allocation_rule_id=(select id from public.allocation_rules where name='Geral piloto')and farm_id='aa000000-0000-0000-0000-000000000103';
select test_general.ok((select sum(percentage)=200 from public.entry_allocations a join public.financial_entries e on e.id=a.financial_entry_id where e.source_type='IMPORTACAO' and a.allocation_rule_id is not null),'future rule edits do not mutate historical snapshots');
reset role;
select test_general.ok((select count(*)=154 from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9'),'official template remains 154 accounts');
rollback;
