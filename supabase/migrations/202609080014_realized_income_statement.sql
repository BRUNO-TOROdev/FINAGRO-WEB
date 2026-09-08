-- FINAGRO Web — realized DRE, calculated from issue-date allocations and ID mappings.

create index idx_entries_org_issue_reporting
  on public.financial_entries(organization_id, issue_date, chart_account_id)
  where deleted_at is null;

alter table public.report_account_mappings
  drop constraint report_account_mappings_organization_id_reporting_structure_key;
alter table public.report_account_mappings
  add constraint report_account_mappings_organization_id_reporting_structure_key
  unique(organization_id,reporting_structure_id,chart_account_id);

create or replace function private.guard_report_mapping() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.report_lines l where l.id=new.report_line_id and l.organization_id=new.organization_id and l.reporting_structure_id=new.reporting_structure_id and l.line_type='ACCOUNT') then raise exception 'REPORT_MAPPING_REQUIRES_ACCOUNT_LINE'; end if;
 return new;
end$$;
-- Formula operands are explicit managerial roles or previously calculated lines.
-- Account names and directions entered by users are never calculation keys.
with formulas(code, calculation) as (values
 ('DRE.CALC.RECEITA_OPERACIONAL_BRUTA', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"role":"RECEITA_OPERACIONAL","coefficient":1}]}'::jsonb),
 ('DRE.CALC.RECEITA_OPERACIONAL_LIQUIDA', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.RECEITA_OPERACIONAL_BRUTA","coefficient":1},{"role":"DEDUCAO_RECEITA","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.LUCRO_BRUTO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.RECEITA_OPERACIONAL_LIQUIDA","coefficient":1},{"role":"CUSTO","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.MARGEM_CONTRIBUICAO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.LUCRO_BRUTO","coefficient":1},{"role":"DESPESA_VARIAVEL","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.EBIT', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.MARGEM_CONTRIBUICAO","coefficient":1},{"role":"DESPESA_OPERACIONAL","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.RESULTADO_FINANCEIRO_LIQUIDO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"role":"RECEITA_FINANCEIRA","coefficient":1},{"role":"DESPESA_FINANCEIRA","coefficient":-1},{"role":"JUROS_FINANCIAMENTO","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.RESULTADO_NAO_OPERACIONAL', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"role":"RECEITA_NAO_OPERACIONAL","coefficient":1},{"role":"DESPESA_NAO_OPERACIONAL","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.EBT', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.EBIT","coefficient":1},{"line":"DRE.CALC.RESULTADO_FINANCEIRO_LIQUIDO","coefficient":1},{"line":"DRE.CALC.RESULTADO_NAO_OPERACIONAL","coefficient":1}]}'::jsonb),
 ('DRE.CALC.LUCRO_LIQUIDO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.EBT","coefficient":1},{"role":"IMPOSTO_RENDA","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.LUCRO_RETIDO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.LUCRO_LIQUIDO","coefficient":1},{"role":"DIVIDENDO","coefficient":-1}]}'::jsonb)
)
update public.report_line_templates l set calculation=f.calculation
from formulas f join public.reporting_templates t on t.code='DRE'
where l.reporting_template_id=t.id and l.code=f.code;

with formulas(code, calculation) as (values
 ('DRE.CALC.RECEITA_OPERACIONAL_BRUTA', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"role":"RECEITA_OPERACIONAL","coefficient":1}]}'::jsonb),
 ('DRE.CALC.RECEITA_OPERACIONAL_LIQUIDA', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.RECEITA_OPERACIONAL_BRUTA","coefficient":1},{"role":"DEDUCAO_RECEITA","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.LUCRO_BRUTO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.RECEITA_OPERACIONAL_LIQUIDA","coefficient":1},{"role":"CUSTO","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.MARGEM_CONTRIBUICAO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.LUCRO_BRUTO","coefficient":1},{"role":"DESPESA_VARIAVEL","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.EBIT', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.MARGEM_CONTRIBUICAO","coefficient":1},{"role":"DESPESA_OPERACIONAL","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.RESULTADO_FINANCEIRO_LIQUIDO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"role":"RECEITA_FINANCEIRA","coefficient":1},{"role":"DESPESA_FINANCEIRA","coefficient":-1},{"role":"JUROS_FINANCIAMENTO","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.RESULTADO_NAO_OPERACIONAL', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"role":"RECEITA_NAO_OPERACIONAL","coefficient":1},{"role":"DESPESA_NAO_OPERACIONAL","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.EBT', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.EBIT","coefficient":1},{"line":"DRE.CALC.RESULTADO_FINANCEIRO_LIQUIDO","coefficient":1},{"line":"DRE.CALC.RESULTADO_NAO_OPERACIONAL","coefficient":1}]}'::jsonb),
 ('DRE.CALC.LUCRO_LIQUIDO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.EBT","coefficient":1},{"role":"IMPOSTO_RENDA","coefficient":-1}]}'::jsonb),
 ('DRE.CALC.LUCRO_RETIDO', '{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE.CALC.LUCRO_LIQUIDO","coefficient":1},{"role":"DIVIDENDO","coefficient":-1}]}'::jsonb)
)
update public.report_lines l set calculation=f.calculation
from formulas f join public.reporting_structures s on s.code='DRE'
where l.reporting_structure_id=s.id and l.organization_id=s.organization_id and l.code=f.code;

create or replace function public.get_realized_dre(
 p_organization_id uuid, p_start_month date, p_end_month date,
 p_farm_id uuid default null, p_reporting_structure_id uuid default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s_id uuid; calc record; operand jsonb; m date; amount_value numeric(18,2);
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'reports.view') then raise exception 'PERMISSION_DENIED'; end if;
 if date_trunc('month',p_start_month)::date<>p_start_month or date_trunc('month',p_end_month)::date<>p_end_month or p_end_month<p_start_month then raise exception 'INVALID_DRE_PERIOD'; end if;
 select id into s_id from public.reporting_structures where organization_id=p_organization_id and code='DRE' and (p_reporting_structure_id is null or id=p_reporting_structure_id);
 if s_id is null then raise exception 'DRE_STRUCTURE_NOT_FOUND'; end if;
 if p_farm_id is not null and not exists(select 1 from public.farms where id=p_farm_id and organization_id=p_organization_id) then raise exception 'FARM_NOT_FOUND_IN_ORGANIZATION'; end if;

 drop table if exists pg_temp.dre_values,pg_temp.dre_roles,pg_temp.dre_months;
 create temporary table dre_months(period_month date primary key) on commit drop;
 create temporary table dre_values(line_id uuid,period_month date,amount numeric(18,2),primary key(line_id,period_month)) on commit drop;
 create temporary table dre_roles(role text,period_month date,amount numeric(18,2),primary key(role,period_month)) on commit drop;
 insert into pg_temp.dre_months select generate_series(p_start_month,p_end_month,interval '1 month')::date;

 insert into pg_temp.dre_roles
 select rm.managerial_role,date_trunc('month',e.issue_date)::date,sum(a.allocated_amount)::numeric(18,2)
 from public.financial_entries e join public.entry_allocations a on a.organization_id=e.organization_id and a.financial_entry_id=e.id
 join public.report_account_mappings rm on rm.organization_id=e.organization_id and rm.reporting_structure_id=s_id and rm.chart_account_id=e.chart_account_id
 where e.organization_id=p_organization_id and e.deleted_at is null and e.issue_date>=p_start_month and e.issue_date<(p_end_month+interval '1 month') and (p_farm_id is null or a.farm_id=p_farm_id)
 group by rm.managerial_role,date_trunc('month',e.issue_date)::date;

 with recursive descendants(root_id,line_id) as (
   select id,id from public.report_lines where organization_id=p_organization_id and reporting_structure_id=s_id and line_type='ACCOUNT'
   union all select d.root_id,l.id from descendants d join public.report_lines l on l.parent_id=d.line_id and l.organization_id=p_organization_id and l.reporting_structure_id=s_id and l.line_type='ACCOUNT'
 )
 insert into pg_temp.dre_values
 select d.root_id,date_trunc('month',e.issue_date)::date,sum(a.allocated_amount)::numeric(18,2)
 from descendants d join public.report_account_mappings rm on rm.organization_id=p_organization_id and rm.reporting_structure_id=s_id and rm.report_line_id=d.line_id
 join public.financial_entries e on e.organization_id=p_organization_id and e.chart_account_id=rm.chart_account_id and e.deleted_at is null
 join public.entry_allocations a on a.organization_id=e.organization_id and a.financial_entry_id=e.id
 where e.issue_date>=p_start_month and e.issue_date<(p_end_month+interval '1 month') and (p_farm_id is null or a.farm_id=p_farm_id)
 group by d.root_id,date_trunc('month',e.issue_date)::date;

 for calc in select * from public.report_lines where organization_id=p_organization_id and reporting_structure_id=s_id and line_type='CALCULATED' order by display_order,code loop
   for m in select period_month from pg_temp.dre_months loop
     amount_value=0;
     for operand in select value from jsonb_array_elements(calc.calculation->'operands') loop
       if operand ? 'role' then amount_value=amount_value+coalesce((select amount from pg_temp.dre_roles where role=operand->>'role' and period_month=m),0)*(operand->>'coefficient')::numeric;
       else amount_value=amount_value+coalesce((select v.amount from pg_temp.dre_values v join public.report_lines l on l.id=v.line_id where l.organization_id=p_organization_id and l.reporting_structure_id=s_id and l.code=operand->>'line' and v.period_month=m),0)*(operand->>'coefficient')::numeric;
       end if;
     end loop;
     insert into pg_temp.dre_values values(calc.id,m,amount_value);
   end loop;
 end loop;

 return jsonb_build_object(
  'structure_id',s_id,'start_month',p_start_month,'end_month',p_end_month,'farm_id',p_farm_id,
  'months',(select jsonb_agg(to_char(period_month,'YYYY-MM-DD') order by period_month) from pg_temp.dre_months),
  'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'parent_id',l.parent_id,'code',l.code,'label',l.label,'line_type',l.line_type,'display_order',l.display_order,'values',coalesce(v.values,'{}'::jsonb),'total',coalesce(v.total,0)) order by l.display_order,l.code),'[]'::jsonb)
    from public.report_lines l left join lateral (select jsonb_object_agg(to_char(dm.period_month,'YYYY-MM-DD'),coalesce(dv.amount,0) order by dm.period_month) values,sum(coalesce(dv.amount,0))::numeric(18,2) total from pg_temp.dre_months dm left join pg_temp.dre_values dv on dv.line_id=l.id and dv.period_month=dm.period_month) v on true
    where l.organization_id=p_organization_id and l.reporting_structure_id=s_id),
  'coverage',(select jsonb_build_object(
    'entries_total',count(distinct e.id),'accounts_total',count(distinct e.chart_account_id),
    'entries_mapped',count(distinct e.id) filter(where rm.id is not null),'accounts_mapped',count(distinct e.chart_account_id) filter(where rm.id is not null),
    'entries_unmapped',count(distinct e.id) filter(where rm.id is null),'accounts_unmapped',count(distinct e.chart_account_id) filter(where rm.id is null),
    'classified_amount',coalesce(sum(a.allocated_amount) filter(where rm.id is not null),0),'unclassified_amount',coalesce(sum(a.allocated_amount) filter(where rm.id is null),0),
    'unmapped',coalesce((select jsonb_agg(x order by x->>'code') from (select jsonb_build_object('account_id',e2.chart_account_id,'code',c.code,'name',c.name,'entry_count',count(distinct e2.id),'amount',sum(a2.allocated_amount)) x from public.financial_entries e2 join public.entry_allocations a2 on a2.organization_id=e2.organization_id and a2.financial_entry_id=e2.id join public.chart_accounts c on c.id=e2.chart_account_id and c.organization_id=e2.organization_id left join public.report_account_mappings rm2 on rm2.organization_id=e2.organization_id and rm2.reporting_structure_id=s_id and rm2.chart_account_id=e2.chart_account_id where e2.organization_id=p_organization_id and e2.deleted_at is null and e2.issue_date>=p_start_month and e2.issue_date<(p_end_month+interval '1 month') and (p_farm_id is null or a2.farm_id=p_farm_id) and rm2.id is null group by e2.chart_account_id,c.code,c.name) q),'[]'::jsonb))
    from public.financial_entries e join public.entry_allocations a on a.organization_id=e.organization_id and a.financial_entry_id=e.id left join public.report_account_mappings rm on rm.organization_id=e.organization_id and rm.reporting_structure_id=s_id and rm.chart_account_id=e.chart_account_id where e.organization_id=p_organization_id and e.deleted_at is null and e.issue_date>=p_start_month and e.issue_date<(p_end_month+interval '1 month') and (p_farm_id is null or a.farm_id=p_farm_id))
 );
end$$;

revoke all on function public.get_realized_dre(uuid,date,date,uuid,uuid) from public;
grant execute on function public.get_realized_dre(uuid,date,date,uuid,uuid) to authenticated;
