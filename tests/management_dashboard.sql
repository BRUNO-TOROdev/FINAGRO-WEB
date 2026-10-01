-- Dashboard is a composition boundary; financial behavior remains covered by each engine suite.
begin;
create schema test_dashboard;
create function test_dashboard.ok(value boolean,message text) returns void language plpgsql as $$begin if not coalesce(value,false) then raise exception 'ASSERTION FAILED: %',message; end if; end$$;

select test_dashboard.ok(to_regprocedure('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)') is not null,'dashboard RPC exists');
select test_dashboard.ok(position('get_realized_dre(' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))>0,'competence dashboard consumes realized DRE');
select test_dashboard.ok(position('get_realized_dre_crop_season(' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))>0,'season dashboard consumes DRE Safra');
select test_dashboard.ok(position('get_realized_cash_flow(' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))>0,'cash dashboard consumes due-date cash flow');
select test_dashboard.ok(position('get_projected_vs_actual(' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))>0,'dashboard consumes projected versus actual');
select test_dashboard.ok(position('financial_entries' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))=0,'dashboard does not reimplement entries aggregation');
select test_dashboard.ok(position('settlements' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))=0,'dashboard does not use settlements');
select test_dashboard.ok(position('account.name' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))=0 and position('source_name' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))=0,'dashboard is independent of account names');
select test_dashboard.ok(position('has_permission' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))>0,'dashboard enforces reports permission');
select test_dashboard.ok(position('PUBLICADO' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))=0,'publication validation remains delegated to comparison engine');
select test_dashboard.ok(position('auth.uid() is null' in pg_get_functiondef('public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)'::regprocedure))>0,'anonymous invocation is rejected inside the authorization boundary');
select test_dashboard.ok(has_function_privilege('authenticated','public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid)','execute'),'authenticated role can execute dashboard subject to authorization');
rollback;

