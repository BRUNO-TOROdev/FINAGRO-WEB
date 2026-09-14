-- FINAGRO Web — Fluxo de Caixa FINAGRO realizado por vencimento.

create index idx_entries_org_due_reporting
  on public.financial_entries(organization_id,due_date,chart_account_id)
  where deleted_at is null;

-- Abertura mensal é uma linha calculada. A conta Saldo Inicial continua lançável
-- somente para informar a abertura do primeiro mês do período consultado.
insert into public.report_line_templates(id,reporting_template_id,parent_id,code,label,line_type,display_order,calculation,confidence)
select '61739bf0-dcad-52a0-94aa-71bf58d60001',t.id,null,'DFC_PREVISTO.CALC.SALDO_INICIAL_MENSAL','SALDO INICIAL','CALCULATED',400000,
       '{"source":"FINAGRO_SPREADSHEET_FORMULA","operation":"OPENING_BALANCE","opening_role":"SALDO_INICIAL","prior_line":"DFC_PREVISTO.CALC.SALDO_CAIXA_ACUMULADO","total_mode":"FIRST"}'::jsonb,'confirmed_spreadsheet'
from public.reporting_templates t where t.code='DFC_PREVISTO'
on conflict(reporting_template_id,code) do update set calculation=excluded.calculation,display_order=excluded.display_order;

insert into public.report_lines(organization_id,reporting_structure_id,source_template_line_id,parent_id,code,label,line_type,display_order,calculation)
select s.organization_id,s.id,l.id,null,l.code,l.label,l.line_type,l.display_order,l.calculation
from public.reporting_structures s join public.report_line_templates l on l.reporting_template_id=s.reporting_template_id
where s.code='DFC_PREVISTO' and l.code='DFC_PREVISTO.CALC.SALDO_INICIAL_MENSAL'
on conflict(organization_id,reporting_structure_id,code) do update set calculation=excluded.calculation,display_order=excluded.display_order;

with formulas(code,display_order,calculation) as (values
 ('DFC_PREVISTO.CALC.TOTAL_ENTRADAS',100000,'{"source":"FINAGRO_SPREADSHEET_FORMULA","operation":"SUM_DIRECTION","direction":"ENTRADA"}'::jsonb),
 ('DFC_PREVISTO.CALC.TOTAL_SAIDAS',200000,'{"source":"FINAGRO_SPREADSHEET_FORMULA","operation":"SUM_DIRECTION","direction":"SAIDA"}'::jsonb),
 ('DFC_PREVISTO.CALC.GERACAO_CAIXA',300000,'{"source":"FINAGRO_SPREADSHEET_FORMULA","operation":"LINEAR","operands":[{"line":"DFC_PREVISTO.CALC.TOTAL_ENTRADAS","coefficient":1},{"line":"DFC_PREVISTO.CALC.TOTAL_SAIDAS","coefficient":-1}]}'::jsonb),
 ('DFC_PREVISTO.CALC.SALDO_CAIXA_ACUMULADO',500000,'{"source":"FINAGRO_SPREADSHEET_FORMULA","operation":"LINEAR","total_mode":"LAST","operands":[{"line":"DFC_PREVISTO.CALC.SALDO_INICIAL_MENSAL","coefficient":1},{"line":"DFC_PREVISTO.CALC.GERACAO_CAIXA","coefficient":1}]}'::jsonb)
)
update public.report_line_templates l set calculation=f.calculation,display_order=f.display_order
from formulas f join public.reporting_templates t on t.code='DFC_PREVISTO'
where l.reporting_template_id=t.id and l.code=f.code;

update public.report_lines l set calculation=lt.calculation,display_order=lt.display_order
from public.reporting_structures s join public.report_line_templates lt on lt.reporting_template_id=s.reporting_template_id
where l.reporting_structure_id=s.id and l.organization_id=s.organization_id and s.code='DFC_PREVISTO' and l.code=lt.code and lt.line_type='CALCULATED';

create or replace function public.get_realized_cash_flow(
 p_organization_id uuid,p_start_month date,p_end_month date,
 p_farm_id uuid default null,p_reporting_structure_id uuid default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s_id uuid; calc record; operand jsonb; m date; prior_m date; amount_value numeric(18,2); operation text;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'reports.view') then raise exception 'PERMISSION_DENIED'; end if;
 if date_trunc('month',p_start_month)::date<>p_start_month or date_trunc('month',p_end_month)::date<>p_end_month or p_end_month<p_start_month then raise exception 'INVALID_CASH_FLOW_PERIOD'; end if;
 select id into s_id from public.reporting_structures where organization_id=p_organization_id and code='DFC_PREVISTO' and (p_reporting_structure_id is null or id=p_reporting_structure_id);
 if s_id is null then raise exception 'CASH_FLOW_STRUCTURE_NOT_FOUND'; end if;
 if p_farm_id is not null and not exists(select 1 from public.farms where id=p_farm_id and organization_id=p_organization_id) then raise exception 'FARM_NOT_FOUND_IN_ORGANIZATION'; end if;

 drop table if exists pg_temp.cf_months,pg_temp.cf_facts,pg_temp.cf_values;
 create temporary table cf_months(period_month date primary key) on commit drop;
 create temporary table cf_facts(entry_id uuid,account_id uuid,line_id uuid,role text,direction text,period_month date,amount numeric(18,2)) on commit drop;
 create temporary table cf_values(line_id uuid,period_month date,amount numeric(18,2),primary key(line_id,period_month)) on commit drop;
 insert into pg_temp.cf_months select generate_series(p_start_month,p_end_month,interval '1 month')::date;
 insert into pg_temp.cf_facts
 select e.id,e.chart_account_id,rm.report_line_id,rm.managerial_role,rm.typical_direction,date_trunc('month',e.due_date)::date,sum(a.allocated_amount)::numeric(18,2)
 from public.financial_entries e join public.entry_allocations a on a.organization_id=e.organization_id and a.financial_entry_id=e.id
 join public.report_account_mappings rm on rm.organization_id=e.organization_id and rm.reporting_structure_id=s_id and rm.chart_account_id=e.chart_account_id
 where e.organization_id=p_organization_id and e.deleted_at is null and e.due_date>=p_start_month and e.due_date<(p_end_month+interval '1 month') and (p_farm_id is null or a.farm_id=p_farm_id)
 group by e.id,e.chart_account_id,rm.report_line_id,rm.managerial_role,rm.typical_direction,date_trunc('month',e.due_date)::date;

 with recursive descendants(root_id,line_id) as (
  select id,id from public.report_lines where organization_id=p_organization_id and reporting_structure_id=s_id and line_type='ACCOUNT'
  union all select d.root_id,l.id from descendants d join public.report_lines l on l.parent_id=d.line_id and l.organization_id=p_organization_id and l.reporting_structure_id=s_id and l.line_type='ACCOUNT'
 )
 insert into pg_temp.cf_values select d.root_id,f.period_month,sum(f.amount)::numeric(18,2) from descendants d join pg_temp.cf_facts f on f.line_id=d.line_id group by d.root_id,f.period_month;

 for m in select period_month from pg_temp.cf_months order by period_month loop
  for calc in select * from public.report_lines where organization_id=p_organization_id and reporting_structure_id=s_id and line_type='CALCULATED' order by display_order,code loop
   operation=calc.calculation->>'operation'; amount_value=0;
   if operation='SUM_DIRECTION' then
    select coalesce(sum(amount),0)::numeric(18,2) into amount_value from pg_temp.cf_facts where period_month=m and direction=calc.calculation->>'direction';
   elsif operation='OPENING_BALANCE' then
    if m=p_start_month then
     select coalesce(sum(amount),0)::numeric(18,2) into amount_value from pg_temp.cf_facts where period_month=m and role=calc.calculation->>'opening_role';
    else
     prior_m=(m-interval '1 month')::date;
     select coalesce(v.amount,0) into amount_value from pg_temp.cf_values v join public.report_lines l on l.id=v.line_id where l.organization_id=p_organization_id and l.reporting_structure_id=s_id and l.code=calc.calculation->>'prior_line' and v.period_month=prior_m;
    end if;
   elsif operation='LINEAR' then
    for operand in select value from jsonb_array_elements(calc.calculation->'operands') loop
     amount_value=amount_value+coalesce((select v.amount from pg_temp.cf_values v join public.report_lines l on l.id=v.line_id where l.organization_id=p_organization_id and l.reporting_structure_id=s_id and l.code=operand->>'line' and v.period_month=m),0)*(operand->>'coefficient')::numeric;
    end loop;
   else raise exception 'UNSUPPORTED_CASH_FLOW_OPERATION'; end if;
   insert into pg_temp.cf_values values(calc.id,m,amount_value);
  end loop;
 end loop;

 return jsonb_build_object('structure_id',s_id,'start_month',p_start_month,'end_month',p_end_month,'farm_id',p_farm_id,
 'months',(select jsonb_agg(to_char(period_month,'YYYY-MM-DD') order by period_month) from pg_temp.cf_months),
 'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'parent_id',l.parent_id,'code',l.code,'label',l.label,'line_type',l.line_type,'display_order',l.display_order,'values',coalesce(v.values,'{}'::jsonb),'total',coalesce(v.total,0)) order by l.display_order,l.code),'[]'::jsonb) from public.report_lines l left join lateral(select jsonb_object_agg(to_char(cm.period_month,'YYYY-MM-DD'),coalesce(cv.amount,0) order by cm.period_month) values,(case l.calculation->>'total_mode' when 'FIRST' then max(coalesce(cv.amount,0)) filter(where cm.period_month=p_start_month) when 'LAST' then max(coalesce(cv.amount,0)) filter(where cm.period_month=p_end_month) else sum(coalesce(cv.amount,0)) end)::numeric(18,2) total from pg_temp.cf_months cm left join pg_temp.cf_values cv on cv.line_id=l.id and cv.period_month=cm.period_month)v on true where l.organization_id=p_organization_id and l.reporting_structure_id=s_id),
 'coverage',(select jsonb_build_object('entries_total',count(distinct e.id),'accounts_total',count(distinct e.chart_account_id),'entries_mapped',count(distinct e.id) filter(where rm.id is not null),'accounts_mapped',count(distinct e.chart_account_id) filter(where rm.id is not null),'entries_unmapped',count(distinct e.id) filter(where rm.id is null),'accounts_unmapped',count(distinct e.chart_account_id) filter(where rm.id is null),'classified_amount',coalesce(sum(a.allocated_amount) filter(where rm.id is not null),0),'unclassified_amount',coalesce(sum(a.allocated_amount) filter(where rm.id is null),0),'unmapped',coalesce((select jsonb_agg(x order by x->>'code') from(select jsonb_build_object('account_id',e2.chart_account_id,'code',c.code,'name',c.name,'entry_count',count(distinct e2.id),'amount',sum(a2.allocated_amount))x from public.financial_entries e2 join public.entry_allocations a2 on a2.organization_id=e2.organization_id and a2.financial_entry_id=e2.id join public.chart_accounts c on c.id=e2.chart_account_id and c.organization_id=e2.organization_id left join public.report_account_mappings rm2 on rm2.organization_id=e2.organization_id and rm2.reporting_structure_id=s_id and rm2.chart_account_id=e2.chart_account_id where e2.organization_id=p_organization_id and e2.deleted_at is null and e2.due_date>=p_start_month and e2.due_date<(p_end_month+interval '1 month') and (p_farm_id is null or a2.farm_id=p_farm_id) and rm2.id is null group by e2.chart_account_id,c.code,c.name)q),'[]'::jsonb)) from public.financial_entries e join public.entry_allocations a on a.organization_id=e.organization_id and a.financial_entry_id=e.id left join public.report_account_mappings rm on rm.organization_id=e.organization_id and rm.reporting_structure_id=s_id and rm.chart_account_id=e.chart_account_id where e.organization_id=p_organization_id and e.deleted_at is null and e.due_date>=p_start_month and e.due_date<(p_end_month+interval '1 month') and (p_farm_id is null or a.farm_id=p_farm_id)));
end$$;

revoke all on function public.get_realized_cash_flow(uuid,date,date,uuid,uuid) from public;
grant execute on function public.get_realized_cash_flow(uuid,date,date,uuid,uuid) to authenticated;
