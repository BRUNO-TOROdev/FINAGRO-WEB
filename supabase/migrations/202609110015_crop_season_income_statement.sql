-- FINAGRO Web — DRE Safra via configuração sazonal explícita e snapshots de apropriação.

create table public.report_season_rule_templates (
 id uuid primary key, reporting_template_id uuid not null references public.reporting_templates(id) on delete cascade,
 chart_template_item_id uuid not null, chart_template_id uuid not null,
 rule_type text not null check(rule_type in ('SELECTED_SEASONS_CURRENT_AND_PRIOR_YEAR')),
 prior_month_offset integer not null default 12 check(prior_month_offset between 1 and 60),
 confidence text not null check(confidence in ('confirmed_spreadsheet','confirmed_tutorial','confirmed_both')),
 evidence text not null,
 unique(reporting_template_id,chart_template_item_id),
 foreign key(chart_template_item_id,chart_template_id) references public.chart_account_template_items(id,template_id)
);

create table public.report_season_rules (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null,
 reporting_structure_id uuid not null, report_account_mapping_id uuid not null,
 source_template_rule_id uuid references public.report_season_rule_templates(id),
 rule_type text not null check(rule_type in ('SELECTED_SEASONS_CURRENT_AND_PRIOR_YEAR')),
 prior_month_offset integer not null default 12 check(prior_month_offset between 1 and 60),
 evidence text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(organization_id,reporting_structure_id,report_account_mapping_id), unique(id,organization_id),
 foreign key(reporting_structure_id,organization_id) references public.reporting_structures(id,organization_id) on delete cascade,
 foreign key(report_account_mapping_id,organization_id) references public.report_account_mappings(id,organization_id) on delete cascade
);

create or replace function private.guard_report_season_rule() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.report_account_mappings m join public.reporting_structures s on s.id=m.reporting_structure_id and s.organization_id=m.organization_id where m.id=new.report_account_mapping_id and m.organization_id=new.organization_id and m.reporting_structure_id=new.reporting_structure_id and s.code='DRE_SAFRA') then raise exception 'SEASON_RULE_REQUIRES_DRE_SAFRA_MAPPING'; end if;
 return new;
end$$;
create trigger trg_report_season_rules_guard before insert or update on public.report_season_rules for each row execute function private.guard_report_season_rule();
create trigger trg_report_season_rules_updated_at before update on public.report_season_rules for each row execute function private.set_updated_at();
create trigger trg_report_season_rules_audit after insert or update or delete on public.report_season_rules for each row execute function private.audit_row_change();

alter table public.report_season_rule_templates enable row level security;
alter table public.report_season_rules enable row level security;
create policy report_season_rule_templates_read on public.report_season_rule_templates for select to authenticated using(true);
create policy report_season_rules_read on public.report_season_rules for select to authenticated using(private.has_permission(organization_id,'reports.view'));
create policy report_season_rules_write on public.report_season_rules for all to authenticated using(private.has_permission(organization_id,'chart_accounts.manage')) with check(private.has_permission(organization_id,'chart_accounts.manage'));

insert into public.report_season_rule_templates(id,reporting_template_id,chart_template_id,chart_template_item_id,rule_type,prior_month_offset,confidence,evidence) values
('8b5d0823-4d5f-5e6f-8001-000000000001','354d5bb6-7376-5daa-b2fa-c2871da2a9ac','3269e51b-12de-5887-a85c-4461af91b4e9','f22aeff5-3aef-5895-94bb-18e3eede3776','SELECTED_SEASONS_CURRENT_AND_PRIOR_YEAR',12,'confirmed_spreadsheet','DRE SAFRA: Adubo; Safra e Safrinha no mês exibido e no mesmo mês do ano anterior.'),
('8b5d0823-4d5f-5e6f-8001-000000000002','354d5bb6-7376-5daa-b2fa-c2871da2a9ac','3269e51b-12de-5887-a85c-4461af91b4e9','2c2a6c30-57c2-58c8-9356-4f41f07f7975','SELECTED_SEASONS_CURRENT_AND_PRIOR_YEAR',12,'confirmed_spreadsheet','DRE SAFRA: Fretes sobre Matéria Prima; Safra e Safrinha no mês exibido e no mesmo mês do ano anterior.'),
('8b5d0823-4d5f-5e6f-8001-000000000003','354d5bb6-7376-5daa-b2fa-c2871da2a9ac','3269e51b-12de-5887-a85c-4461af91b4e9','6db7317c-49ed-52d6-b04b-4008c8355e93','SELECTED_SEASONS_CURRENT_AND_PRIOR_YEAR',12,'confirmed_spreadsheet','DRE SAFRA: Produtos Quimicos; Safra e Safrinha no mês exibido e no mesmo mês do ano anterior.'),
('8b5d0823-4d5f-5e6f-8001-000000000004','354d5bb6-7376-5daa-b2fa-c2871da2a9ac','3269e51b-12de-5887-a85c-4461af91b4e9','1a531c3b-9343-5190-98cc-dbda49efde24','SELECTED_SEASONS_CURRENT_AND_PRIOR_YEAR',12,'confirmed_spreadsheet','DRE SAFRA: Sementes; Safra e Safrinha no mês exibido e no mesmo mês do ano anterior.');

create or replace function private.copy_report_season_rule() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.report_season_rules(organization_id,reporting_structure_id,report_account_mapping_id,source_template_rule_id,rule_type,prior_month_offset,evidence)
 select new.organization_id,new.reporting_structure_id,new.id,r.id,r.rule_type,r.prior_month_offset,r.evidence
 from public.reporting_structures s join public.chart_accounts a on a.id=new.chart_account_id and a.organization_id=new.organization_id
 join public.report_season_rule_templates r on r.reporting_template_id=s.reporting_template_id and r.chart_template_item_id=a.source_template_item_id
 where s.id=new.reporting_structure_id and s.organization_id=new.organization_id on conflict do nothing;
 return new;
end$$;
create trigger trg_copy_report_season_rule after insert on public.report_account_mappings for each row execute function private.copy_report_season_rule();

insert into public.report_season_rules(organization_id,reporting_structure_id,report_account_mapping_id,source_template_rule_id,rule_type,prior_month_offset,evidence)
select m.organization_id,m.reporting_structure_id,m.id,r.id,r.rule_type,r.prior_month_offset,r.evidence
from public.report_account_mappings m join public.reporting_structures s on s.id=m.reporting_structure_id and s.organization_id=m.organization_id
join public.chart_accounts a on a.id=m.chart_account_id and a.organization_id=m.organization_id
join public.report_season_rule_templates r on r.reporting_template_id=s.reporting_template_id and r.chart_template_item_id=a.source_template_item_id
where s.code='DRE_SAFRA' on conflict do nothing;

with formulas(suffix,calculation) as (values
 ('RECEITA_OPERACIONAL_BRUTA','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"role":"RECEITA_OPERACIONAL","coefficient":1}]}'::jsonb),
 ('RECEITA_OPERACIONAL_LIQUIDA','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE_SAFRA.CALC.RECEITA_OPERACIONAL_BRUTA","coefficient":1},{"role":"DEDUCAO_RECEITA","coefficient":-1}]}'::jsonb),
 ('LUCRO_BRUTO','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE_SAFRA.CALC.RECEITA_OPERACIONAL_LIQUIDA","coefficient":1},{"role":"CUSTO","coefficient":-1}]}'::jsonb),
 ('MARGEM_CONTRIBUICAO','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE_SAFRA.CALC.LUCRO_BRUTO","coefficient":1},{"role":"DESPESA_VARIAVEL","coefficient":-1}]}'::jsonb),
 ('EBIT','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE_SAFRA.CALC.MARGEM_CONTRIBUICAO","coefficient":1},{"role":"DESPESA_OPERACIONAL","coefficient":-1}]}'::jsonb),
 ('RESULTADO_FINANCEIRO_LIQUIDO','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"role":"RECEITA_FINANCEIRA","coefficient":1},{"role":"DESPESA_FINANCEIRA","coefficient":-1},{"role":"JUROS_FINANCIAMENTO","coefficient":-1}]}'::jsonb),
 ('RESULTADO_NAO_OPERACIONAL','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"role":"RECEITA_NAO_OPERACIONAL","coefficient":1},{"role":"DESPESA_NAO_OPERACIONAL","coefficient":-1}]}'::jsonb),
 ('EBT','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE_SAFRA.CALC.EBIT","coefficient":1},{"line":"DRE_SAFRA.CALC.RESULTADO_FINANCEIRO_LIQUIDO","coefficient":1},{"line":"DRE_SAFRA.CALC.RESULTADO_NAO_OPERACIONAL","coefficient":1}]}'::jsonb),
 ('LUCRO_LIQUIDO','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE_SAFRA.CALC.EBT","coefficient":1},{"role":"IMPOSTO_RENDA","coefficient":-1}]}'::jsonb),
 ('LUCRO_RETIDO','{"source":"FINAGRO_SPREADSHEET_FORMULA","operands":[{"line":"DRE_SAFRA.CALC.LUCRO_LIQUIDO","coefficient":1},{"role":"DIVIDENDO","coefficient":-1}]}'::jsonb)
)
update public.report_line_templates l set calculation=f.calculation from formulas f join public.reporting_templates t on t.code='DRE_SAFRA' where l.reporting_template_id=t.id and l.code='DRE_SAFRA.CALC.'||f.suffix;
with formulas(suffix,calculation) as (select replace(l.code,'DRE_SAFRA.CALC.',''),l.calculation from public.report_line_templates l join public.reporting_templates t on t.id=l.reporting_template_id where t.code='DRE_SAFRA' and l.line_type='CALCULATED')
update public.report_lines l set calculation=f.calculation from formulas f join public.reporting_structures s on s.code='DRE_SAFRA' where l.reporting_structure_id=s.id and l.organization_id=s.organization_id and l.code='DRE_SAFRA.CALC.'||f.suffix;

create or replace function public.get_realized_dre_crop_season(p_organization_id uuid,p_crop_season_id uuid,p_second_crop_season_id uuid,p_farm_id uuid default null,p_reporting_structure_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s_id uuid; cycle_start date; cycle_end date; calc record; operand jsonb; m date; amount_value numeric(18,2);
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'reports.view') then raise exception 'PERMISSION_DENIED'; end if;
 select date_trunc('month',starts_on)::date,date_trunc('month',ends_on)::date into cycle_start,cycle_end from public.crop_seasons where id=p_crop_season_id and organization_id=p_organization_id and season_type='PRINCIPAL' and starts_on is not null and ends_on is not null;
 if cycle_start is null then raise exception 'PRIMARY_CROP_SEASON_INVALID'; end if;
 if not exists(select 1 from public.crop_seasons where id=p_second_crop_season_id and organization_id=p_organization_id and season_type='SAFRINHA') then raise exception 'SECOND_CROP_SEASON_INVALID'; end if;
 select id into s_id from public.reporting_structures where organization_id=p_organization_id and code='DRE_SAFRA' and (p_reporting_structure_id is null or id=p_reporting_structure_id);
 if s_id is null then raise exception 'DRE_CROP_SEASON_STRUCTURE_NOT_FOUND'; end if;
 if p_farm_id is not null and not exists(select 1 from public.farms where id=p_farm_id and organization_id=p_organization_id) then raise exception 'FARM_NOT_FOUND_IN_ORGANIZATION'; end if;
 drop table if exists pg_temp.ds_months,pg_temp.ds_facts,pg_temp.ds_unmapped,pg_temp.ds_values,pg_temp.ds_roles;
 create temporary table ds_months(period_month date primary key) on commit drop;
 create temporary table ds_facts(entry_id uuid,account_id uuid,mapping_id uuid,line_id uuid,role text,period_month date,amount numeric(18,2),is_seasonal boolean,missing_season_rule boolean) on commit drop;
 create temporary table ds_unmapped(entry_id uuid,account_id uuid,amount numeric(18,2)) on commit drop;
 create temporary table ds_values(line_id uuid,period_month date,amount numeric(18,2),primary key(line_id,period_month)) on commit drop;
 create temporary table ds_roles(role text,period_month date,amount numeric(18,2),primary key(role,period_month)) on commit drop;
 insert into pg_temp.ds_months select generate_series(cycle_start,cycle_end,interval '1 month')::date;
 insert into pg_temp.ds_facts
 select e.id,e.chart_account_id,rm.id,rm.report_line_id,rm.managerial_role,dm.period_month,sum(a.allocated_amount)::numeric(18,2),sr.id is not null,(rm.crop_filter_mode<>'NONE' and sr.id is null)
 from public.financial_entries e join public.entry_allocations a on a.organization_id=e.organization_id and a.financial_entry_id=e.id
 join public.report_account_mappings rm on rm.organization_id=e.organization_id and rm.reporting_structure_id=s_id and rm.chart_account_id=e.chart_account_id
 left join public.report_season_rules sr on sr.organization_id=rm.organization_id and sr.reporting_structure_id=rm.reporting_structure_id and sr.report_account_mapping_id=rm.id
 join pg_temp.ds_months dm on case when sr.id is null then date_trunc('month',e.issue_date)::date=dm.period_month else e.crop_season_id in (p_crop_season_id,p_second_crop_season_id) and date_trunc('month',e.issue_date)::date in (dm.period_month,(dm.period_month-(sr.prior_month_offset||' months')::interval)::date) end
 where e.organization_id=p_organization_id and e.deleted_at is null and (p_farm_id is null or a.farm_id=p_farm_id)
 group by e.id,e.chart_account_id,rm.id,rm.report_line_id,rm.managerial_role,dm.period_month,sr.id,rm.crop_filter_mode;
 insert into pg_temp.ds_unmapped
 select e.id,e.chart_account_id,sum(a.allocated_amount)::numeric(18,2) from public.financial_entries e join public.entry_allocations a on a.organization_id=e.organization_id and a.financial_entry_id=e.id
 left join public.report_account_mappings rm on rm.organization_id=e.organization_id and rm.reporting_structure_id=s_id and rm.chart_account_id=e.chart_account_id
 where e.organization_id=p_organization_id and e.deleted_at is null and e.issue_date>=cycle_start and e.issue_date<(cycle_end+interval '1 month') and (p_farm_id is null or a.farm_id=p_farm_id) and rm.id is null group by e.id,e.chart_account_id;
 insert into pg_temp.ds_roles select role,period_month,sum(amount)::numeric(18,2) from pg_temp.ds_facts where not missing_season_rule group by role,period_month;
 with recursive descendants(root_id,line_id) as (select id,id from public.report_lines where organization_id=p_organization_id and reporting_structure_id=s_id and line_type='ACCOUNT' union all select d.root_id,l.id from descendants d join public.report_lines l on l.parent_id=d.line_id and l.organization_id=p_organization_id and l.reporting_structure_id=s_id and l.line_type='ACCOUNT')
 insert into pg_temp.ds_values select d.root_id,f.period_month,sum(f.amount)::numeric(18,2) from descendants d join pg_temp.ds_facts f on f.line_id=d.line_id where not f.missing_season_rule group by d.root_id,f.period_month;
 for calc in select * from public.report_lines where organization_id=p_organization_id and reporting_structure_id=s_id and line_type='CALCULATED' order by display_order,code loop
  for m in select period_month from pg_temp.ds_months loop amount_value=0;
   for operand in select value from jsonb_array_elements(calc.calculation->'operands') loop
    if operand ? 'role' then amount_value=amount_value+coalesce((select amount from pg_temp.ds_roles where role=operand->>'role' and period_month=m),0)*(operand->>'coefficient')::numeric;
    else amount_value=amount_value+coalesce((select v.amount from pg_temp.ds_values v join public.report_lines l on l.id=v.line_id where l.code=operand->>'line' and v.period_month=m),0)*(operand->>'coefficient')::numeric; end if;
   end loop; insert into pg_temp.ds_values values(calc.id,m,amount_value);
  end loop;
 end loop;
 return jsonb_build_object('structure_id',s_id,'crop_season_id',p_crop_season_id,'second_crop_season_id',p_second_crop_season_id,'start_month',cycle_start,'end_month',cycle_end,'farm_id',p_farm_id,
 'months',(select jsonb_agg(to_char(period_month,'YYYY-MM-DD') order by period_month) from pg_temp.ds_months),
 'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'parent_id',l.parent_id,'code',l.code,'label',l.label,'line_type',l.line_type,'display_order',l.display_order,'values',coalesce(v.values,'{}'::jsonb),'total',coalesce(v.total,0)) order by l.display_order,l.code),'[]'::jsonb) from public.report_lines l left join lateral(select jsonb_object_agg(to_char(dm.period_month,'YYYY-MM-DD'),coalesce(dv.amount,0) order by dm.period_month) values,sum(coalesce(dv.amount,0))::numeric(18,2) total from pg_temp.ds_months dm left join pg_temp.ds_values dv on dv.line_id=l.id and dv.period_month=dm.period_month)v on true where l.organization_id=p_organization_id and l.reporting_structure_id=s_id),
 'coverage',jsonb_build_object('entries_total',(select count(distinct entry_id) from (select entry_id from pg_temp.ds_facts union all select entry_id from pg_temp.ds_unmapped)x),'accounts_total',(select count(distinct account_id) from (select account_id from pg_temp.ds_facts union all select account_id from pg_temp.ds_unmapped)x),'entries_mapped',(select count(distinct entry_id) from pg_temp.ds_facts where not missing_season_rule),'accounts_mapped',(select count(distinct account_id) from pg_temp.ds_facts where not missing_season_rule),'entries_unmapped',(select count(distinct entry_id) from pg_temp.ds_unmapped),'accounts_unmapped',(select count(distinct account_id) from pg_temp.ds_unmapped),'classified_amount',(select coalesce(sum(amount),0) from pg_temp.ds_facts where not missing_season_rule),'unclassified_amount',(select coalesce(sum(amount),0) from pg_temp.ds_unmapped),'unmapped',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('account_id',u.account_id,'code',c.code,'name',c.name,'entry_count',count(distinct u.entry_id),'amount',sum(u.amount))x from pg_temp.ds_unmapped u join public.chart_accounts c on c.id=u.account_id group by u.account_id,c.code,c.name)q),'seasonal_config_missing',(select coalesce(jsonb_agg(x),'[]'::jsonb) from(select jsonb_build_object('account_id',f.account_id,'code',c.code,'name',c.name,'entry_count',count(distinct f.entry_id),'amount',sum(f.amount))x from pg_temp.ds_facts f join public.chart_accounts c on c.id=f.account_id where f.missing_season_rule group by f.account_id,c.code,c.name)q))) ;
end$$;
revoke all on function public.get_realized_dre_crop_season(uuid,uuid,uuid,uuid,uuid) from public;
grant execute on function public.get_realized_dre_crop_season(uuid,uuid,uuid,uuid,uuid) to authenticated;
grant select on public.report_season_rule_templates,public.report_season_rules to authenticated;
grant insert,update,delete on public.report_season_rules to authenticated;
