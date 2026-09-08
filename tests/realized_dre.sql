-- FINAGRO Web — realized DRE calculation, mapping coverage and hostile RLS cases.
begin;
create schema test_dre;
create function test_dre.ok(c boolean,m text) returns void language plpgsql set search_path='' as $$begin if c is not true then raise exception 'TEST FAILED: %',m;end if;end$$;
create function test_dre.err(q text,e text) returns void language plpgsql set search_path='' as $$declare m text;begin begin execute q;exception when others then m=sqlerrm;if position(e in m)=0 then raise exception 'TEST FAILED expected %, got %',e,m;end if;return;end;raise exception 'TEST FAILED expected %',e;end$$;
create function test_dre.value_at(j jsonb,c text,m text) returns numeric language sql immutable set search_path='' as $$select coalesce((x->'values'->>$3)::numeric,0) from jsonb_array_elements($1->'lines') x where x->>'code'=$2$$;
grant usage on schema test_dre to authenticated;grant execute on all functions in schema test_dre to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('a1000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','dre-owner@example.test','x',now(),'{}','{}',now(),now()),
('a1000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','dre-read@example.test','x',now(),'{}','{}',now(),now()),
('b1000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','dre-outsider@example.test','x',now(),'{}','{}',now(),now());
insert into public.organizations(id,legal_name) values('a1000000-0000-0000-0000-000000000010','DRE A'),('b1000000-0000-0000-0000-000000000020','DRE B');
select private.seed_default_roles('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000000001');select private.seed_default_roles('b1000000-0000-0000-0000-000000000020','b1000000-0000-0000-0000-000000000001');
insert into public.memberships(organization_id,user_id,role_id) select 'a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000000002',id from public.roles where organization_id='a1000000-0000-0000-0000-000000000010' and name='Somente leitura';
insert into public.farms(id,organization_id,name) values('a1000000-0000-0000-0000-000000000101','a1000000-0000-0000-0000-000000000010','HS'),('a1000000-0000-0000-0000-000000000102','a1000000-0000-0000-0000-000000000010','Santo Angelo'),('a1000000-0000-0000-0000-000000000103','a1000000-0000-0000-0000-000000000010','Escondida'),('b1000000-0000-0000-0000-000000000101','b1000000-0000-0000-0000-000000000020','B');
insert into public.crop_seasons(id,organization_id,name,season_type) values('a1000000-0000-0000-0000-000000000201','a1000000-0000-0000-0000-000000000010','Safra','PRINCIPAL');
insert into public.allocation_rules(id,organization_id,crop_season_id,name,is_active) values('a1000000-0000-0000-0000-000000000301','a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000000201','45/40/15',true);
insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage) values
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000000301','a1000000-0000-0000-0000-000000000101',45),
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000000301','a1000000-0000-0000-0000-000000000102',40),
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000000301','a1000000-0000-0000-0000-000000000103',15);

set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
select public.apply_chart_account_template('a1000000-0000-0000-0000-000000000010','3269e51b-12de-5887-a85c-4461af91b4e9');
select public.apply_reporting_template('a1000000-0000-0000-0000-000000000010','7b80964a-3a28-5f9e-ab2f-d0e15291f835');
reset role;
create temporary table ac as select code,id from public.chart_accounts where organization_id='a1000000-0000-0000-0000-000000000010';
update public.chart_accounts set allows_allocation=true where id=(select id from ac where code='FINAGRO-V1-G020-S001');
insert into public.chart_accounts(id,organization_id,code,name,managerial_type,nature) values('a1000000-0000-0000-0000-000000000999','a1000000-0000-0000-0000-000000000010','UNMAPPED-X','Nome irrelevante','OUTRO','NEUTRA');
insert into public.bank_accounts(id,organization_id,bank_name,account_number) values('a1000000-0000-0000-0000-000000000401','a1000000-0000-0000-0000-000000000010','Teste','1');
insert into public.financial_entries(id,organization_id,entry_direction,status,issue_date,due_date,description,chart_account_id,crop_season_id,amount) values
('a1000000-0000-0000-0000-000000001001','a1000000-0000-0000-0000-000000000010','ENTRADA','PENDENTE','2027-01-10','2027-05-10','Receita Jan',(select id from ac where code='FINAGRO-V1-G020-S001'),'a1000000-0000-0000-0000-000000000201',100),
('a1000000-0000-0000-0000-000000001002','a1000000-0000-0000-0000-000000000010','ENTRADA','AGENDADO','2027-02-10','2027-06-10','Receita Fev',(select id from ac where code='FINAGRO-V1-G020-S001'),'a1000000-0000-0000-0000-000000000201',200),
('a1000000-0000-0000-0000-000000001003','a1000000-0000-0000-0000-000000000010','SAIDA','PENDENTE','2027-01-12','2027-07-12','Custo',(select id from ac where code='FINAGRO-V1-G002-S001'),'a1000000-0000-0000-0000-000000000201',40),
('a1000000-0000-0000-0000-000000001004','a1000000-0000-0000-0000-000000000010','ENTRADA','PENDENTE','2027-01-15','2027-01-15','Sem mapping','a1000000-0000-0000-0000-000000000999',null,10),
('a1000000-0000-0000-0000-000000001005','a1000000-0000-0000-0000-000000000010','SAIDA','PENDENTE','2027-01-20','2027-02-20','Principal',(select id from ac where code='FINAGRO-V1-G011-S001'),null,50),
('a1000000-0000-0000-0000-000000001006','a1000000-0000-0000-0000-000000000010','SAIDA','PENDENTE','2027-01-21','2027-02-21','Juros',(select id from ac where code='FINAGRO-V1-G008-S001'),null,5);
insert into public.entry_allocations(organization_id,financial_entry_id,farm_id,allocation_rule_id,percentage,allocated_amount,snapshot_rule_name,snapshot_crop_season_name) values
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000001001','a1000000-0000-0000-0000-000000000101',null,100,100,null,null),
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000001002','a1000000-0000-0000-0000-000000000101','a1000000-0000-0000-0000-000000000301',45,90,'45/40/15','Safra'),
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000001002','a1000000-0000-0000-0000-000000000102','a1000000-0000-0000-0000-000000000301',40,80,'45/40/15','Safra'),
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000001002','a1000000-0000-0000-0000-000000000103','a1000000-0000-0000-0000-000000000301',15,30,'45/40/15','Safra'),
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000001003','a1000000-0000-0000-0000-000000000101',null,100,40,null,null),
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000001004','a1000000-0000-0000-0000-000000000101',null,100,10,null,null),
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000001005','a1000000-0000-0000-0000-000000000101',null,100,50,null,null),
('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000001006','a1000000-0000-0000-0000-000000000101',null,100,5,null,null);
insert into public.settlements(organization_id,financial_entry_id,bank_account_id,settled_at,amount) values('a1000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000001003','a1000000-0000-0000-0000-000000000401','2027-09-01',40);
update public.financial_entries set status='PAGO' where id='a1000000-0000-0000-0000-000000001003';
set constraints all immediate;set constraints all deferred;

set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
create temporary table result as select public.get_realized_dre('a1000000-0000-0000-0000-000000000010','2027-01-01','2027-02-01') j;
select test_dre.ok(test_dre.value_at((select j from result),'DRE.CALC.RECEITA_OPERACIONAL_BRUTA','2027-01-01')=100,'issue date drives January despite May due date');
select test_dre.ok(test_dre.value_at((select j from result),'DRE.CALC.RECEITA_OPERACIONAL_BRUTA','2027-02-01')=200,'all statuses participate and months total exactly');
select test_dre.ok(test_dre.value_at((select j from result),'DRE.CALC.LUCRO_BRUTO','2027-01-01')=60,'cost is subtracted by configured role');
select test_dre.ok(test_dre.value_at((select j from result),'DRE.CALC.RESULTADO_FINANCEIRO_LIQUIDO','2027-01-01')=-5,'interest follows its own DRE mapping');
select test_dre.ok(((select j from result)->'coverage'->>'entries_total')::int=6 and ((select j from result)->'coverage'->>'entries_unmapped')::int=2 and ((select j from result)->'coverage'->>'unclassified_amount')::numeric=60,'unmapped account and financing principal remain visible in coverage');
select test_dre.ok(test_dre.value_at(public.get_realized_dre('a1000000-0000-0000-0000-000000000010','2027-01-01','2027-02-01','a1000000-0000-0000-0000-000000000101'),'DRE.CALC.RECEITA_OPERACIONAL_BRUTA','2027-02-01')=90,'45 percent snapshot by farm');
select test_dre.ok(test_dre.value_at(public.get_realized_dre('a1000000-0000-0000-0000-000000000010','2027-01-01','2027-02-01','a1000000-0000-0000-0000-000000000102'),'DRE.CALC.RECEITA_OPERACIONAL_BRUTA','2027-02-01')=80 and test_dre.value_at(public.get_realized_dre('a1000000-0000-0000-0000-000000000010','2027-01-01','2027-02-01','a1000000-0000-0000-0000-000000000103'),'DRE.CALC.RECEITA_OPERACIONAL_BRUTA','2027-02-01')=30,'40/15 snapshot exact');
select test_dre.ok(test_dre.value_at((select j from result),'DRE.CALC.RECEITA_OPERACIONAL_BRUTA','2027-02-01')=90+80+30,'farms reconcile consolidated without double counting parent and child mappings');
select test_dre.err($$select public.get_realized_dre('a1000000-0000-0000-0000-000000000010','2027-01-01','2027-02-01','b1000000-0000-0000-0000-000000000101')$$,'FARM_NOT_FOUND_IN_ORGANIZATION');
select test_dre.err($$select public.get_realized_dre('a1000000-0000-0000-0000-000000000010','2027-01-01','2027-02-01',null,'b1000000-0000-0000-0000-000000000999')$$,'DRE_STRUCTURE_NOT_FOUND');
reset role;update public.allocation_rule_items set percentage=50 where allocation_rule_id='a1000000-0000-0000-0000-000000000301' and farm_id='a1000000-0000-0000-0000-000000000101';update public.allocation_rule_items set percentage=35 where allocation_rule_id='a1000000-0000-0000-0000-000000000301' and farm_id='a1000000-0000-0000-0000-000000000102';set constraints all immediate;set constraints all deferred;
set local role authenticated;select set_config('request.jwt.claim.role','authenticated',true);select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
select test_dre.ok(test_dre.value_at(public.get_realized_dre('a1000000-0000-0000-0000-000000000010','2027-01-01','2027-02-01','a1000000-0000-0000-0000-000000000101'),'DRE.CALC.RECEITA_OPERACIONAL_BRUTA','2027-02-01')=90,'read-only reads and current rule does not recalculate history');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
select test_dre.err($$select public.get_realized_dre('a1000000-0000-0000-0000-000000000010','2027-01-01','2027-02-01')$$,'PERMISSION_DENIED');
rollback;
