-- FINAGRO Web — explicit projected versus actual managerial analysis.

create table public.report_line_comparison_templates (
 id uuid primary key default gen_random_uuid(),
 comparison_view text not null check(comparison_view in ('DRE_COMPETENCIA','DRE_SAFRA','DFC_VENCIMENTO')),
 projected_line_template_id uuid not null references public.report_line_templates(id),
 actual_line_template_id uuid not null references public.report_line_templates(id),
 created_at timestamptz not null default now(),
 unique(comparison_view,projected_line_template_id),
 unique(comparison_view,actual_line_template_id)
);
alter table public.report_line_comparison_templates enable row level security;
create policy report_line_comparison_templates_read on public.report_line_comparison_templates for select to authenticated using(true);
grant select on public.report_line_comparison_templates to authenticated;

-- Account lines are paired through the same immutable chart-template item.
insert into public.report_line_comparison_templates(comparison_view,projected_line_template_id,actual_line_template_id)
select v.view_code,p.report_line_template_id,a.report_line_template_id
from (values ('DRE_COMPETENCIA','PROJECAO_DRE','DRE'),('DRE_SAFRA','PROJECAO_DRE','DRE_SAFRA'),('DFC_VENCIMENTO','PROJECAO_DFC','DFC_PREVISTO')) v(view_code,projected_code,actual_code)
join public.reporting_templates pt on pt.code=v.projected_code
join public.reporting_templates at on at.code=v.actual_code
join public.report_account_template_mappings p on p.reporting_template_id=pt.id
join public.report_account_template_mappings a on a.reporting_template_id=at.id and a.chart_template_item_id=p.chart_template_item_id
on conflict do nothing;

-- Calculated lines are paired once, by stable template IDs. Codes are used only
-- during this migration to establish the durable relationship, never at runtime.
insert into public.report_line_comparison_templates(comparison_view,projected_line_template_id,actual_line_template_id)
select v.view_code,p.id,a.id
from (values ('DRE_COMPETENCIA','PROJECAO_DRE','DRE'),('DRE_SAFRA','PROJECAO_DRE','DRE_SAFRA'),('DFC_VENCIMENTO','PROJECAO_DFC','DFC_PREVISTO')) v(view_code,projected_code,actual_code)
join public.reporting_templates pt on pt.code=v.projected_code
join public.reporting_templates at on at.code=v.actual_code
join public.report_line_templates p on p.reporting_template_id=pt.id and p.line_type='CALCULATED'
join public.report_line_templates a on a.reporting_template_id=at.id and a.line_type='CALCULATED'
  and split_part(a.code,'.CALC.',2)=split_part(p.code,'.CALC.',2)
on conflict do nothing;

-- Projection formulas mirror their own corresponding report structures.
update public.report_line_templates p set calculation=jsonb_set(a.calculation,'{operands}',
 coalesce((select jsonb_agg(case when x ? 'line' then jsonb_set(x,'{line}',to_jsonb(replace(x->>'line','DRE.','PROJECAO_DRE.'))) else x end) from jsonb_array_elements(a.calculation->'operands') x),'[]'::jsonb))
from public.report_line_comparison_templates c join public.report_line_templates a on a.id=c.actual_line_template_id
where c.comparison_view='DRE_COMPETENCIA' and p.id=c.projected_line_template_id and p.line_type='CALCULATED';

-- DFC needs the explicit monthly opening line on the projection side too.
insert into public.report_line_templates(id,reporting_template_id,parent_id,code,label,line_type,display_order,calculation,confidence)
select '71739bf0-dcad-52a0-94aa-71bf58d60001',t.id,null,'PROJECAO_DFC.CALC.SALDO_INICIAL_MENSAL','SALDO INICIAL','CALCULATED',400000,
 '{"source":"FINAGRO_SPREADSHEET_FORMULA","operation":"OPENING_BALANCE","opening_role":"SALDO_INICIAL","prior_line":"PROJECAO_DFC.CALC.SALDO_CAIXA_ACUMULADO","total_mode":"FIRST"}'::jsonb,'confirmed_spreadsheet'
from public.reporting_templates t where t.code='PROJECAO_DFC' on conflict(reporting_template_id,code) do nothing;
insert into public.report_lines(organization_id,reporting_structure_id,source_template_line_id,parent_id,code,label,line_type,display_order,calculation)
select s.organization_id,s.id,t.id,null,t.code,t.label,t.line_type,t.display_order,t.calculation from public.reporting_structures s join public.report_line_templates t on t.reporting_template_id=s.reporting_template_id
where s.code='PROJECAO_DFC' and t.code='PROJECAO_DFC.CALC.SALDO_INICIAL_MENSAL' on conflict(organization_id,reporting_structure_id,code) do nothing;
insert into public.report_line_comparison_templates(comparison_view,projected_line_template_id,actual_line_template_id)
select 'DFC_VENCIMENTO',p.id,a.id from public.report_line_templates p join public.reporting_templates pt on pt.id=p.reporting_template_id and pt.code='PROJECAO_DFC'
join public.report_line_templates a on a.code='DFC_PREVISTO.CALC.SALDO_INICIAL_MENSAL' where p.code='PROJECAO_DFC.CALC.SALDO_INICIAL_MENSAL' on conflict do nothing;

with f(code,display_order,calculation) as (values
 ('PROJECAO_DFC.CALC.TOTAL_ENTRADAS',100000,'{"operation":"SUM_DIRECTION","direction":"ENTRADA"}'::jsonb),
 ('PROJECAO_DFC.CALC.TOTAL_SAIDAS',200000,'{"operation":"SUM_DIRECTION","direction":"SAIDA"}'::jsonb),
 ('PROJECAO_DFC.CALC.GERACAO_CAIXA',300000,'{"operation":"LINEAR","operands":[{"line":"PROJECAO_DFC.CALC.TOTAL_ENTRADAS","coefficient":1},{"line":"PROJECAO_DFC.CALC.TOTAL_SAIDAS","coefficient":-1}]}'::jsonb),
 ('PROJECAO_DFC.CALC.SALDO_CAIXA_ACUMULADO',500000,'{"operation":"LINEAR","total_mode":"LAST","operands":[{"line":"PROJECAO_DFC.CALC.SALDO_INICIAL_MENSAL","coefficient":1},{"line":"PROJECAO_DFC.CALC.GERACAO_CAIXA","coefficient":1}]}'::jsonb))
update public.report_line_templates l set calculation=f.calculation,display_order=f.display_order from f where l.code=f.code;
update public.report_lines l set calculation=t.calculation,display_order=t.display_order from public.report_line_templates t where l.source_template_line_id=t.id and l.line_type='CALCULATED';

create or replace function private.get_budget_projection_report(p_organization_id uuid,p_budget_version_id uuid,p_basis text,p_start_month date,p_end_month date,p_farm_id uuid,p_structure_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s_id uuid; s_code text; calc record; operand jsonb; m date; prior_m date; amount_value numeric(18,2); operation text;
begin
 s_code=case p_basis when 'DRE' then 'PROJECAO_DRE' when 'DFC' then 'PROJECAO_DFC' else null end;
 if s_code is null then raise exception 'INVALID_PROJECTION_BASIS'; end if;
 if not exists(select 1 from public.budget_versions where id=p_budget_version_id and organization_id=p_organization_id and status='PUBLICADO') then raise exception 'PUBLISHED_BUDGET_VERSION_NOT_FOUND'; end if;
 select id into s_id from public.reporting_structures where organization_id=p_organization_id and code=s_code and (p_structure_id is null or id=p_structure_id);
 if s_id is null then raise exception 'PROJECTION_STRUCTURE_NOT_FOUND'; end if;
 drop table if exists pg_temp.bp_months,pg_temp.bp_facts,pg_temp.bp_values,pg_temp.bp_roles;
 create temporary table bp_months(period_month date primary key) on commit drop;
 create temporary table bp_facts(account_id uuid,line_id uuid,role text,direction text,period_month date,amount numeric(18,2)) on commit drop;
 create temporary table bp_values(line_id uuid,period_month date,amount numeric(18,2),primary key(line_id,period_month)) on commit drop;
 create temporary table bp_roles(role text,period_month date,amount numeric(18,2),primary key(role,period_month)) on commit drop;
 insert into pg_temp.bp_months select generate_series(p_start_month,p_end_month,interval '1 month')::date;
 insert into pg_temp.bp_facts select v.chart_account_id,rm.report_line_id,rm.managerial_role,rm.typical_direction,v.period_month,sum(v.amount)::numeric(18,2)
 from public.v_budget_projection_monthly v join public.report_account_mappings rm on rm.organization_id=v.organization_id and rm.reporting_structure_id=s_id and rm.chart_account_id=v.chart_account_id
 where v.organization_id=p_organization_id and v.budget_version_id=p_budget_version_id and v.status='PUBLICADO' and v.projection_basis=p_basis and v.period_month between p_start_month and p_end_month and (p_farm_id is null or v.farm_id=p_farm_id)
 group by v.chart_account_id,rm.report_line_id,rm.managerial_role,rm.typical_direction,v.period_month;
 insert into pg_temp.bp_roles select role,period_month,sum(amount)::numeric(18,2) from pg_temp.bp_facts group by role,period_month;
 with recursive d(root_id,line_id) as (select id,id from public.report_lines where organization_id=p_organization_id and reporting_structure_id=s_id and line_type='ACCOUNT' union all select d.root_id,l.id from d join public.report_lines l on l.parent_id=d.line_id and l.organization_id=p_organization_id and l.reporting_structure_id=s_id and l.line_type='ACCOUNT')
 insert into pg_temp.bp_values select d.root_id,f.period_month,sum(f.amount)::numeric(18,2) from d join pg_temp.bp_facts f on f.line_id=d.line_id group by d.root_id,f.period_month;
 for m in select period_month from pg_temp.bp_months order by period_month loop
  for calc in select * from public.report_lines where organization_id=p_organization_id and reporting_structure_id=s_id and line_type='CALCULATED' order by display_order,code loop
   operation=calc.calculation->>'operation'; amount_value=0;
   if p_basis='DRE' then
    for operand in select value from jsonb_array_elements(calc.calculation->'operands') loop
     if operand ? 'role' then amount_value=amount_value+coalesce((select amount from pg_temp.bp_roles where role=operand->>'role' and period_month=m),0)*(operand->>'coefficient')::numeric;
     else amount_value=amount_value+coalesce((select v.amount from pg_temp.bp_values v join public.report_lines l on l.id=v.line_id where l.code=operand->>'line' and v.period_month=m),0)*(operand->>'coefficient')::numeric; end if;
    end loop;
   elsif operation='SUM_DIRECTION' then select coalesce(sum(amount),0)::numeric(18,2) into amount_value from pg_temp.bp_facts where period_month=m and direction=calc.calculation->>'direction';
   elsif operation='OPENING_BALANCE' then
    if m=p_start_month then select coalesce(sum(amount),0)::numeric(18,2) into amount_value from pg_temp.bp_facts where period_month=m and role=calc.calculation->>'opening_role';
    else prior_m=(m-interval '1 month')::date; select coalesce(v.amount,0) into amount_value from pg_temp.bp_values v join public.report_lines l on l.id=v.line_id where l.code=calc.calculation->>'prior_line' and v.period_month=prior_m; end if;
   elsif operation='LINEAR' then for operand in select value from jsonb_array_elements(calc.calculation->'operands') loop amount_value=amount_value+coalesce((select v.amount from pg_temp.bp_values v join public.report_lines l on l.id=v.line_id where l.code=operand->>'line' and v.period_month=m),0)*(operand->>'coefficient')::numeric; end loop;
   else raise exception 'UNSUPPORTED_PROJECTION_OPERATION'; end if;
   insert into pg_temp.bp_values values(calc.id,m,amount_value);
  end loop;
 end loop;
 return jsonb_build_object('structure_id',s_id,'months',(select jsonb_agg(to_char(period_month,'YYYY-MM-DD') order by period_month) from pg_temp.bp_months),'lines',(select jsonb_agg(jsonb_build_object('id',l.id,'parent_id',l.parent_id,'code',l.code,'label',l.label,'line_type',l.line_type,'display_order',l.display_order,'values',v.values,'total',v.total) order by l.display_order,l.code) from public.report_lines l cross join lateral(select jsonb_object_agg(to_char(m.period_month,'YYYY-MM-DD'),coalesce(x.amount,0) order by m.period_month) values,(case l.calculation->>'total_mode' when 'FIRST' then max(coalesce(x.amount,0)) filter(where m.period_month=p_start_month) when 'LAST' then max(coalesce(x.amount,0)) filter(where m.period_month=p_end_month) else sum(coalesce(x.amount,0)) end)::numeric(18,2) total from pg_temp.bp_months m left join pg_temp.bp_values x on x.line_id=l.id and x.period_month=m.period_month)v where l.organization_id=p_organization_id and l.reporting_structure_id=s_id));
end$$;
revoke all on function private.get_budget_projection_report(uuid,uuid,text,date,date,uuid,uuid) from public;

create or replace function public.get_projected_vs_actual(p_organization_id uuid,p_budget_version_id uuid,p_comparison_view text,p_start_month date default null,p_end_month date default null,p_farm_id uuid default null,p_crop_season_id uuid default null,p_second_crop_season_id uuid default null,p_projected_structure_id uuid default null,p_actual_structure_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare projected jsonb; actual jsonb; basis text; start_m date; end_m date; plan record; pair record; m text; pv numeric; av numeric;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'reports.view') then raise exception 'PERMISSION_DENIED'; end if;
 if p_comparison_view not in ('DRE_COMPETENCIA','DRE_SAFRA','DFC_VENCIMENTO') then raise exception 'INVALID_COMPARISON_VIEW'; end if;
 select p.name plan_name,v.name version_name,v.version_number,p.starts_on,p.ends_on into plan from public.budget_versions v join public.budget_plans p on p.id=v.budget_plan_id and p.organization_id=v.organization_id where v.id=p_budget_version_id and v.organization_id=p_organization_id and v.status='PUBLICADO';
 if not found then raise exception 'PUBLISHED_BUDGET_VERSION_NOT_FOUND'; end if;
 if p_farm_id is not null and not exists(select 1 from public.farms where id=p_farm_id and organization_id=p_organization_id) then raise exception 'FARM_NOT_FOUND_IN_ORGANIZATION'; end if;
 basis=case when p_comparison_view='DFC_VENCIMENTO' then 'DFC' else 'DRE' end;
 if p_comparison_view='DRE_SAFRA' then
  if p_crop_season_id is null or p_second_crop_season_id is null then raise exception 'CROP_SEASONS_REQUIRED'; end if;
  actual=public.get_realized_dre_crop_season(p_organization_id,p_crop_season_id,p_second_crop_season_id,p_farm_id,p_actual_structure_id);
  start_m=(actual->>'start_month')::date; end_m=(actual->>'end_month')::date;
 else
  start_m=coalesce(p_start_month,plan.starts_on); end_m=coalesce(p_end_month,plan.ends_on);
  if date_trunc('month',start_m)::date<>start_m or date_trunc('month',end_m)::date<>end_m or end_m<start_m then raise exception 'INVALID_COMPARISON_PERIOD'; end if;
  actual=case when p_comparison_view='DRE_COMPETENCIA' then public.get_realized_dre(p_organization_id,start_m,end_m,p_farm_id,p_actual_structure_id) else public.get_realized_cash_flow(p_organization_id,start_m,end_m,p_farm_id,p_actual_structure_id) end;
 end if;
 projected=private.get_budget_projection_report(p_organization_id,p_budget_version_id,basis,start_m,end_m,p_farm_id,p_projected_structure_id);
 drop table if exists pg_temp.pva_months,pg_temp.pva_lines,pg_temp.pva_values;
 create temporary table pva_months(month_key text primary key,display_order int) on commit drop;
 create temporary table pva_lines(line_id uuid,parent_id uuid,code text,label text,line_type text,display_order int,projected_total numeric,actual_total numeric,total_mode text,primary key(line_id)) on commit drop;
 create temporary table pva_values(line_id uuid,month_key text,projected numeric,actual numeric,primary key(line_id,month_key)) on commit drop;
 insert into pg_temp.pva_months select value,ordinality from jsonb_array_elements_text(actual->'months') with ordinality;
 for pair in select c.*,pl.id projected_id,al.id actual_id,al.parent_id,al.code,al.label,al.line_type,al.display_order,al.calculation, pj.value projected_line,aj.value actual_line from public.report_line_comparison_templates c join public.report_lines pl on pl.source_template_line_id=c.projected_line_template_id and pl.organization_id=p_organization_id and pl.reporting_structure_id=(projected->>'structure_id')::uuid join public.report_lines al on al.source_template_line_id=c.actual_line_template_id and al.organization_id=p_organization_id and al.reporting_structure_id=(actual->>'structure_id')::uuid join lateral (select value from jsonb_array_elements(projected->'lines') where value->>'id'=pl.id::text) pj on true join lateral (select value from jsonb_array_elements(actual->'lines') where value->>'id'=al.id::text) aj on true where c.comparison_view=p_comparison_view order by al.display_order loop
  insert into pg_temp.pva_lines values(pair.actual_id,pair.parent_id,pair.code,pair.label,pair.line_type,pair.display_order,(pair.projected_line->>'total')::numeric,(pair.actual_line->>'total')::numeric,pair.calculation->>'total_mode');
  for m in select month_key from pg_temp.pva_months order by display_order loop
   pv=coalesce((pair.projected_line->'values'->>m)::numeric,0); av=coalesce((pair.actual_line->'values'->>m)::numeric,0); insert into pg_temp.pva_values values(pair.actual_id,m,pv,av);
  end loop;
 end loop;
 return jsonb_build_object('comparison_view',p_comparison_view,'budget',jsonb_build_object('plan_name',plan.plan_name,'version_id',p_budget_version_id,'version_name',plan.version_name,'version_number',plan.version_number,'status','PUBLICADO','starts_on',plan.starts_on,'ends_on',plan.ends_on),'start_month',start_m,'end_month',end_m,'farm_id',p_farm_id,'crop_season_id',p_crop_season_id,'second_crop_season_id',p_second_crop_season_id,'months',actual->'months','coverage',actual->'coverage','lines',(select coalesce(jsonb_agg(jsonb_build_object('id',l.line_id,'parent_id',l.parent_id,'code',l.code,'label',l.label,'line_type',l.line_type,'display_order',l.display_order,'values',(select jsonb_object_agg(v.month_key,jsonb_build_object('projected',v.projected,'actual',v.actual,'variance_amount',v.actual-v.projected,'variance_percent',case when v.projected=0 and v.actual=0 then 0 when v.projected=0 then null else round((v.actual/v.projected-1)*100,4) end,'warning',case when v.projected=0 and v.actual<>0 then 'Realizado sem valor projetado' end) order by mm.display_order) from pg_temp.pva_values v join pg_temp.pva_months mm on mm.month_key=v.month_key where v.line_id=l.line_id),'total',jsonb_build_object('projected',l.projected_total,'actual',l.actual_total,'variance_amount',l.actual_total-l.projected_total,'variance_percent',case when l.projected_total=0 and l.actual_total=0 then 0 when l.projected_total=0 then null else round((l.actual_total/l.projected_total-1)*100,4) end,'warning',case when l.projected_total=0 and l.actual_total<>0 then 'Realizado sem valor projetado' end,'aggregation',coalesce(l.total_mode,'SUM'))) order by l.display_order,l.code),'[]'::jsonb) from pg_temp.pva_lines l));
end$$;
revoke all on function public.get_projected_vs_actual(uuid,uuid,text,date,date,uuid,uuid,uuid,uuid,uuid) from public;
grant execute on function public.get_projected_vs_actual(uuid,uuid,text,date,date,uuid,uuid,uuid,uuid,uuid) to authenticated;
