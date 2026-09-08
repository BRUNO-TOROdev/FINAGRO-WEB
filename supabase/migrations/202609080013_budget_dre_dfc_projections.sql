-- FINAGRO Web — budget versions and independent DRE/DFC monthly projections.

create table public.budget_plans (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 name text not null, starts_on date not null, ends_on date not null, crop_season_id uuid,
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(id,organization_id), unique(organization_id,name),
 foreign key(crop_season_id,organization_id) references public.crop_seasons(id,organization_id),
 check(date_trunc('month',starts_on)::date=starts_on), check(date_trunc('month',ends_on)::date=ends_on), check(ends_on>=starts_on)
);
create table public.budget_versions (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, budget_plan_id uuid not null,
 version_number integer not null check(version_number>0), name text not null,
 status text not null default 'RASCUNHO' check(status in ('RASCUNHO','PUBLICADO','ARQUIVADO')),
 based_on_version_id uuid, published_at timestamptz, published_by uuid references auth.users(id),
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(id,organization_id), unique(budget_plan_id,version_number),
 foreign key(budget_plan_id,organization_id) references public.budget_plans(id,organization_id) on delete cascade,
 foreign key(based_on_version_id,organization_id) references public.budget_versions(id,organization_id),
 check((status='PUBLICADO' and published_at is not null and published_by is not null) or status<>'PUBLICADO')
);

alter table public.budgets drop constraint budgets_status_check;
alter table public.budgets add constraint budgets_status_check check(status in ('RASCUNHO','PUBLICADO','ARQUIVADO'));
alter table public.budgets add column budget_version_id uuid;
alter table public.budgets add constraint budgets_version_org_fkey foreign key(budget_version_id,organization_id) references public.budget_versions(id,organization_id) on delete cascade;
create unique index budgets_version_type_unique on public.budgets(budget_version_id,budget_type) where budget_version_id is not null;

alter table public.budget_items add column direct_farm_id uuid;
alter table public.budget_items add column allocation_rule_id uuid;
alter table public.budget_items add constraint budget_items_direct_farm_org_fkey foreign key(direct_farm_id,organization_id) references public.farms(id,organization_id);
alter table public.budget_items add constraint budget_items_rule_org_fkey foreign key(allocation_rule_id,organization_id) references public.allocation_rules(id,organization_id);
alter table public.budget_items add constraint budget_items_allocation_choice check((direct_farm_id is not null)::integer+(allocation_rule_id is not null)::integer<=1) not valid;
create index budget_items_month_dimensions on public.budget_items(organization_id,budget_id,period_month,chart_account_id,crop_season_id,direct_farm_id,allocation_rule_id);

alter table public.budget_plans enable row level security;
alter table public.budget_versions enable row level security;
create policy budget_plans_read on public.budget_plans for select to authenticated using(private.has_permission(organization_id,'budgets.view'));
create policy budget_plans_write on public.budget_plans for all to authenticated using(private.has_permission(organization_id,'budgets.manage')) with check(private.has_permission(organization_id,'budgets.manage'));
create policy budget_versions_read on public.budget_versions for select to authenticated using(private.has_permission(organization_id,'budgets.view'));
create policy budget_versions_write on public.budget_versions for all to authenticated using(private.has_permission(organization_id,'budgets.manage')) with check(private.has_permission(organization_id,'budgets.manage'));
grant select,insert,update,delete on public.budget_plans,public.budget_versions to authenticated;

create trigger trg_budget_plans_updated_at before update on public.budget_plans for each row execute function private.set_updated_at();
create trigger trg_budget_versions_updated_at before update on public.budget_versions for each row execute function private.set_updated_at();
create trigger trg_budget_plans_audit after insert or update or delete on public.budget_plans for each row execute function private.audit_row_change();
create trigger trg_budget_versions_audit after insert or update or delete on public.budget_versions for each row execute function private.audit_row_change();

create or replace function private.guard_budget_history() returns trigger language plpgsql security definer set search_path='' as $$
declare version_status text; version_id uuid;
begin
 if tg_table_name='budget_versions' then
   if tg_op='DELETE' and old.status<>'RASCUNHO' then raise exception 'PUBLISHED_BUDGET_VERSION_IS_IMMUTABLE'; end if;
   if tg_op='UPDATE' and old.status in ('PUBLICADO','ARQUIVADO') and not(old.status='PUBLICADO' and new.status='ARQUIVADO' and row(new.organization_id,new.budget_plan_id,new.version_number,new.name,new.based_on_version_id)=row(old.organization_id,old.budget_plan_id,old.version_number,old.name,old.based_on_version_id)) then raise exception 'PUBLISHED_BUDGET_VERSION_IS_IMMUTABLE'; end if;
   return coalesce(new,old);
 end if;
 if tg_table_name='budgets' then version_id=coalesce(new.budget_version_id,old.budget_version_id);
 elsif tg_table_name='budget_items' then select b.budget_version_id into version_id from public.budgets b where b.id=coalesce(new.budget_id,old.budget_id);
 else select b.budget_version_id into version_id from public.budget_items i join public.budgets b on b.id=i.budget_id where i.id=coalesce(new.budget_item_id,old.budget_item_id); end if;
 if version_id is not null then select status into version_status from public.budget_versions where id=version_id; end if;
 if version_status in ('PUBLICADO','ARQUIVADO') then raise exception 'PUBLISHED_BUDGET_VERSION_IS_IMMUTABLE'; end if;
 return coalesce(new,old);
end$$;
create trigger trg_budget_versions_history before update or delete on public.budget_versions for each row execute function private.guard_budget_history();
create trigger trg_budgets_history before insert or update or delete on public.budgets for each row execute function private.guard_budget_history();
create trigger trg_budget_items_history before insert or update or delete on public.budget_items for each row execute function private.guard_budget_history();
create trigger trg_budget_allocations_history before insert or update or delete on public.budget_item_allocations for each row execute function private.guard_budget_history();

create or replace function private.rebuild_budget_item_allocations(p_item_id uuid,p_organization_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare item public.budget_items%rowtype; r record; remaining numeric(18,2); part numeric(18,2); rule_name text;
begin
 select * into item from public.budget_items where id=p_item_id and organization_id=p_organization_id;
 if not found then raise exception 'BUDGET_ITEM_NOT_FOUND'; end if;
 delete from public.budget_item_allocations where budget_item_id=item.id and organization_id=item.organization_id;
 if item.direct_farm_id is not null then
   if not exists(select 1 from public.farms where id=item.direct_farm_id and organization_id=item.organization_id and is_active) then raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION'; end if;
   insert into public.budget_item_allocations(organization_id,budget_item_id,farm_id,percentage,allocated_amount) values(item.organization_id,item.id,item.direct_farm_id,100,item.amount); return;
 end if;
 select name into rule_name from public.allocation_rules where id=item.allocation_rule_id and organization_id=item.organization_id and is_active and crop_season_id is not distinct from item.crop_season_id;
 if rule_name is null then raise exception 'ACTIVE_ALLOCATION_RULE_MUST_MATCH_BUDGET_SEASON'; end if;
 remaining=item.amount;
 for r in select ri.*,row_number() over(order by ri.farm_id) n,count(*) over() total from public.allocation_rule_items ri where ri.allocation_rule_id=item.allocation_rule_id and ri.organization_id=item.organization_id order by ri.farm_id loop
   part=case when r.n=r.total then remaining else round(item.amount*r.percentage/100,2) end; remaining=remaining-part;
   insert into public.budget_item_allocations(organization_id,budget_item_id,farm_id,allocation_rule_id,percentage,allocated_amount,snapshot_rule_name) values(item.organization_id,item.id,r.farm_id,item.allocation_rule_id,r.percentage,part,rule_name);
 end loop;
 if remaining<>0 or (select coalesce(sum(percentage),0) from public.budget_item_allocations where budget_item_id=item.id)<>100 or (select coalesce(sum(allocated_amount),0) from public.budget_item_allocations where budget_item_id=item.id)<>item.amount then raise exception 'BUDGET_ALLOCATION_MUST_MATCH_ITEM'; end if;
end$$;

create or replace function public.create_budget_plan(p_organization_id uuid,p_name text,p_starts_on date,p_ends_on date,p_crop_season_id uuid default null,p_version_name text default 'V1') returns uuid language plpgsql security definer set search_path='' as $$
declare plan_id uuid; version_id uuid; next_number integer;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'budgets.manage') then raise exception 'PERMISSION_DENIED'; end if;
 if date_trunc('month',p_starts_on)::date<>p_starts_on or date_trunc('month',p_ends_on)::date<>p_ends_on or p_ends_on<p_starts_on then raise exception 'BUDGET_PERIOD_MUST_USE_CLOSED_MONTHS'; end if;
 if p_crop_season_id is not null and not exists(select 1 from public.crop_seasons where id=p_crop_season_id and organization_id=p_organization_id) then raise exception 'BUDGET_CROP_SEASON_NOT_FOUND'; end if;
 insert into public.budget_plans(organization_id,name,starts_on,ends_on,crop_season_id,created_by) values(p_organization_id,trim(p_name),p_starts_on,p_ends_on,p_crop_season_id,auth.uid()) returning id into plan_id;
 insert into public.budget_versions(organization_id,budget_plan_id,version_number,name,created_by) values(p_organization_id,plan_id,1,trim(p_version_name),auth.uid()) returning id into version_id;
 insert into public.budgets(organization_id,name,budget_type,calendar_year,crop_season_id,status,created_by,budget_version_id) values
 (p_organization_id,trim(p_name)||' · '||trim(p_version_name)||' · DRE','DRE',extract(year from p_starts_on)::integer,p_crop_season_id,'RASCUNHO',auth.uid(),version_id),
 (p_organization_id,trim(p_name)||' · '||trim(p_version_name)||' · DFC','DFC',extract(year from p_starts_on)::integer,p_crop_season_id,'RASCUNHO',auth.uid(),version_id);
 return version_id;
end$$;

create or replace function public.copy_budget_version(p_organization_id uuid,p_source_version_id uuid,p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare source public.budget_versions%rowtype; new_version uuid; projection record; new_budget uuid; item record; new_item uuid;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'budgets.manage') then raise exception 'PERMISSION_DENIED'; end if;
 select * into source from public.budget_versions where id=p_source_version_id and organization_id=p_organization_id;
 if not found then raise exception 'BUDGET_VERSION_NOT_FOUND'; end if;
 insert into public.budget_versions(organization_id,budget_plan_id,version_number,name,based_on_version_id,created_by) select p_organization_id,source.budget_plan_id,coalesce(max(version_number),0)+1,trim(p_name),source.id,auth.uid() from public.budget_versions where budget_plan_id=source.budget_plan_id returning id into new_version;
 for projection in select * from public.budgets where budget_version_id=source.id order by budget_type loop
   insert into public.budgets(organization_id,name,budget_type,calendar_year,crop_season_id,status,created_by,budget_version_id) values(p_organization_id,projection.name||' · cópia',projection.budget_type,projection.calendar_year,projection.crop_season_id,'RASCUNHO',auth.uid(),new_version) returning id into new_budget;
   for item in select * from public.budget_items where budget_id=projection.id order by id loop
     insert into public.budget_items(organization_id,budget_id,period_month,chart_account_id,crop_season_id,amount,notes,direct_farm_id,allocation_rule_id) values(p_organization_id,new_budget,item.period_month,item.chart_account_id,item.crop_season_id,item.amount,item.notes,item.direct_farm_id,item.allocation_rule_id) returning id into new_item;
     insert into public.budget_item_allocations(organization_id,budget_item_id,farm_id,allocation_rule_id,percentage,allocated_amount,snapshot_rule_name) select p_organization_id,new_item,farm_id,allocation_rule_id,percentage,allocated_amount,snapshot_rule_name from public.budget_item_allocations where budget_item_id=item.id;
   end loop;
 end loop; return new_version;
end$$;

create or replace function public.replace_budget_projection_items(p_organization_id uuid,p_budget_version_id uuid,p_projection_basis text,p_items jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare projection_id uuid; plan_id uuid; plan public.budget_plans%rowtype; entry jsonb; new_item uuid; account_id uuid; month_date date; season_id uuid; farm_id uuid; rule_id uuid; amount_value numeric(18,2); structure_code text;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'budgets.manage') then raise exception 'PERMISSION_DENIED'; end if;
 if p_projection_basis not in ('DRE','DFC') then raise exception 'INVALID_PROJECTION_BASIS'; end if;
 select b.id,v.budget_plan_id into projection_id,plan_id from public.budgets b join public.budget_versions v on v.id=b.budget_version_id and v.organization_id=b.organization_id where b.organization_id=p_organization_id and b.budget_version_id=p_budget_version_id and b.budget_type=p_projection_basis and v.status='RASCUNHO';
 if projection_id is null then raise exception 'EDITABLE_BUDGET_PROJECTION_NOT_FOUND'; end if;
 select * into plan from public.budget_plans where id=plan_id and organization_id=p_organization_id;
 if jsonb_typeof(p_items)<>'array' then raise exception 'BUDGET_ITEMS_MUST_BE_ARRAY'; end if;
 delete from public.budget_items where organization_id=p_organization_id and budget_id=projection_id;
 structure_code=case p_projection_basis when 'DRE' then 'PROJECAO_DRE' else 'PROJECAO_DFC' end;
 for entry in select value from jsonb_array_elements(p_items) loop
   account_id=(entry->>'chart_account_id')::uuid; month_date=(entry->>'period_month')::date; season_id=nullif(entry->>'crop_season_id','')::uuid; farm_id=nullif(entry->>'farm_id','')::uuid; rule_id=nullif(entry->>'allocation_rule_id','')::uuid; amount_value=(entry->>'amount')::numeric;
   if amount_value<0 then raise exception 'BUDGET_AMOUNT_MUST_NOT_BE_NEGATIVE'; end if;
   if date_trunc('month',month_date)::date<>month_date or month_date<plan.starts_on or month_date>plan.ends_on then raise exception 'BUDGET_MONTH_OUTSIDE_PLAN'; end if;
   if (farm_id is not null)::integer+(rule_id is not null)::integer<>1 then raise exception 'BUDGET_REQUIRES_FARM_OR_ALLOCATION_RULE'; end if;
   if not exists(select 1 from public.chart_accounts where id=account_id and organization_id=p_organization_id and is_active) then raise exception 'ACTIVE_CHART_ACCOUNT_NOT_FOUND_IN_ORGANIZATION'; end if;
   if season_id is not null and not exists(select 1 from public.crop_seasons where id=season_id and organization_id=p_organization_id) then raise exception 'BUDGET_CROP_SEASON_NOT_FOUND'; end if;
   if farm_id is not null and not exists(select 1 from public.farms where id=farm_id and organization_id=p_organization_id and is_active) then raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION'; end if;
   if rule_id is not null and not exists(select 1 from public.allocation_rules where id=rule_id and organization_id=p_organization_id and is_active and crop_season_id is not distinct from coalesce(season_id,plan.crop_season_id)) then raise exception 'ACTIVE_ALLOCATION_RULE_MUST_MATCH_BUDGET_SEASON'; end if;
   if not exists(select 1 from public.report_account_mappings m join public.reporting_structures s on s.id=m.reporting_structure_id and s.organization_id=m.organization_id where m.organization_id=p_organization_id and m.chart_account_id=account_id and s.code=structure_code) then raise exception 'ACCOUNT_WITHOUT_MANAGERIAL_MAPPING'; end if;
   insert into public.budget_items(organization_id,budget_id,period_month,chart_account_id,crop_season_id,amount,notes,direct_farm_id,allocation_rule_id) values(p_organization_id,projection_id,month_date,account_id,coalesce(season_id,plan.crop_season_id),amount_value,nullif(entry->>'notes',''),farm_id,rule_id) returning id into new_item;
   perform private.rebuild_budget_item_allocations(new_item,p_organization_id);
 end loop; return jsonb_array_length(p_items);
end$$;

create or replace function public.publish_budget_version(p_organization_id uuid,p_budget_version_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare item record;
begin
 if auth.uid() is null or not(private.has_permission(p_organization_id,'budgets.manage') and private.has_permission(p_organization_id,'org.manage')) then raise exception 'PERMISSION_DENIED'; end if;
 if not exists(select 1 from public.budget_versions where id=p_budget_version_id and organization_id=p_organization_id and status='RASCUNHO') then raise exception 'DRAFT_BUDGET_VERSION_NOT_FOUND'; end if;
 for item in select i.id from public.budget_items i join public.budgets b on b.id=i.budget_id and b.organization_id=i.organization_id where b.budget_version_id=p_budget_version_id and i.organization_id=p_organization_id order by i.id loop perform private.rebuild_budget_item_allocations(item.id,p_organization_id); end loop;
 update public.budgets set status='PUBLICADO' where organization_id=p_organization_id and budget_version_id=p_budget_version_id;
 update public.budget_versions set status='PUBLICADO',published_at=now(),published_by=auth.uid() where id=p_budget_version_id and organization_id=p_organization_id;
end$$;

create or replace function public.save_budget_projection_series(p_organization_id uuid,p_budget_version_id uuid,p_projection_basis text,p_chart_account_id uuid,p_crop_season_id uuid,p_farm_id uuid,p_allocation_rule_id uuid,p_values jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare projection_id uuid; plan_id uuid; plan public.budget_plans%rowtype; value_row jsonb; month_date date; amount_value numeric(18,2); item_id uuid; structure_code text;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'budgets.manage') then raise exception 'PERMISSION_DENIED'; end if;
 if p_projection_basis not in('DRE','DFC') or jsonb_typeof(p_values)<>'array' then raise exception 'INVALID_BUDGET_SERIES'; end if;
 select b.id,v.budget_plan_id into projection_id,plan_id from public.budgets b join public.budget_versions v on v.id=b.budget_version_id and v.organization_id=b.organization_id where b.organization_id=p_organization_id and b.budget_version_id=p_budget_version_id and b.budget_type=p_projection_basis and v.status='RASCUNHO';
 if projection_id is null then raise exception 'EDITABLE_BUDGET_PROJECTION_NOT_FOUND'; end if;
 select * into plan from public.budget_plans where id=plan_id and organization_id=p_organization_id;
 if (p_farm_id is not null)::integer+(p_allocation_rule_id is not null)::integer<>1 then raise exception 'BUDGET_REQUIRES_FARM_OR_ALLOCATION_RULE'; end if;
 if not exists(select 1 from public.chart_accounts where id=p_chart_account_id and organization_id=p_organization_id and is_active) then raise exception 'ACTIVE_CHART_ACCOUNT_NOT_FOUND_IN_ORGANIZATION'; end if;
 if p_crop_season_id is not null and not exists(select 1 from public.crop_seasons where id=p_crop_season_id and organization_id=p_organization_id) then raise exception 'BUDGET_CROP_SEASON_NOT_FOUND'; end if;
 if p_farm_id is not null and not exists(select 1 from public.farms where id=p_farm_id and organization_id=p_organization_id and is_active) then raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION'; end if;
 if p_allocation_rule_id is not null and not exists(select 1 from public.allocation_rules where id=p_allocation_rule_id and organization_id=p_organization_id and is_active and crop_season_id is not distinct from coalesce(p_crop_season_id,plan.crop_season_id)) then raise exception 'ACTIVE_ALLOCATION_RULE_MUST_MATCH_BUDGET_SEASON'; end if;
 structure_code=case p_projection_basis when 'DRE' then 'PROJECAO_DRE' else 'PROJECAO_DFC' end;
 if not exists(select 1 from public.report_account_mappings m join public.reporting_structures s on s.id=m.reporting_structure_id and s.organization_id=m.organization_id where m.organization_id=p_organization_id and m.chart_account_id=p_chart_account_id and s.code=structure_code) then raise exception 'ACCOUNT_WITHOUT_MANAGERIAL_MAPPING'; end if;
 delete from public.budget_items where organization_id=p_organization_id and budget_id=projection_id and chart_account_id=p_chart_account_id and crop_season_id is not distinct from coalesce(p_crop_season_id,plan.crop_season_id) and direct_farm_id is not distinct from p_farm_id and allocation_rule_id is not distinct from p_allocation_rule_id;
 for value_row in select value from jsonb_array_elements(p_values) loop
   month_date=(value_row->>'period_month')::date; amount_value=(value_row->>'amount')::numeric;
   if amount_value<0 then raise exception 'BUDGET_AMOUNT_MUST_NOT_BE_NEGATIVE'; end if;
   if date_trunc('month',month_date)::date<>month_date or month_date<plan.starts_on or month_date>plan.ends_on then raise exception 'BUDGET_MONTH_OUTSIDE_PLAN'; end if;
   if amount_value>0 then insert into public.budget_items(organization_id,budget_id,period_month,chart_account_id,crop_season_id,amount,direct_farm_id,allocation_rule_id) values(p_organization_id,projection_id,month_date,p_chart_account_id,coalesce(p_crop_season_id,plan.crop_season_id),amount_value,p_farm_id,p_allocation_rule_id) returning id into item_id; perform private.rebuild_budget_item_allocations(item_id,p_organization_id); end if;
 end loop; return jsonb_array_length(p_values);
end$$;

create or replace function public.archive_budget_version(p_organization_id uuid,p_budget_version_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null or not(private.has_permission(p_organization_id,'budgets.manage') and private.has_permission(p_organization_id,'org.manage')) then raise exception 'PERMISSION_DENIED'; end if; update public.budget_versions set status='ARQUIVADO' where id=p_budget_version_id and organization_id=p_organization_id; if not found then raise exception 'BUDGET_VERSION_NOT_FOUND'; end if; end$$;

revoke all on function private.rebuild_budget_item_allocations(uuid,uuid) from public;
revoke all on function public.create_budget_plan(uuid,text,date,date,uuid,text),public.copy_budget_version(uuid,uuid,text),public.replace_budget_projection_items(uuid,uuid,text,jsonb),public.save_budget_projection_series(uuid,uuid,text,uuid,uuid,uuid,uuid,jsonb),public.publish_budget_version(uuid,uuid),public.archive_budget_version(uuid,uuid) from public;
grant execute on function public.create_budget_plan(uuid,text,date,date,uuid,text),public.copy_budget_version(uuid,uuid,text),public.replace_budget_projection_items(uuid,uuid,text,jsonb),public.save_budget_projection_series(uuid,uuid,text,uuid,uuid,uuid,uuid,jsonb),public.publish_budget_version(uuid,uuid),public.archive_budget_version(uuid,uuid) to authenticated;

create or replace view public.v_budget_projection_monthly with(security_invoker=true) as
select p.organization_id,p.id budget_plan_id,v.id budget_version_id,v.version_number,v.name version_name,v.status,b.budget_type projection_basis,i.period_month,i.chart_account_id,i.crop_season_id,a.farm_id,sum(a.allocated_amount)::numeric(18,2) amount
from public.budget_plans p join public.budget_versions v on v.budget_plan_id=p.id and v.organization_id=p.organization_id join public.budgets b on b.budget_version_id=v.id and b.organization_id=v.organization_id join public.budget_items i on i.budget_id=b.id and i.organization_id=b.organization_id join public.budget_item_allocations a on a.budget_item_id=i.id and a.organization_id=i.organization_id group by p.organization_id,p.id,v.id,v.version_number,v.name,v.status,b.budget_type,i.period_month,i.chart_account_id,i.crop_season_id,a.farm_id;
grant select on public.v_budget_projection_monthly to authenticated;

create or replace view public.v_dre_projected_vs_realized_monthly with(security_invoker=true) as
with realized as (select organization_id,farm_id,crop_season_id,chart_account_id,period_month,sum(allocated_amount) realized_amount from public.v_dre_fact group by 1,2,3,4,5), projected as (select organization_id,farm_id,crop_season_id,chart_account_id,period_month,sum(allocated_amount) projected_amount from public.v_budget_allocated_amounts where budget_type='DRE' and budget_status='PUBLICADO' group by 1,2,3,4,5), keys as (select organization_id,farm_id,crop_season_id,chart_account_id,period_month from realized union select organization_id,farm_id,crop_season_id,chart_account_id,period_month from projected)
select k.*,coalesce(p.projected_amount,0)::numeric(18,2) projected_amount,coalesce(r.realized_amount,0)::numeric(18,2) realized_amount,(coalesce(r.realized_amount,0)-coalesce(p.projected_amount,0))::numeric(18,2) variance_amount,case when coalesce(p.projected_amount,0)=0 then null else round(((coalesce(r.realized_amount,0)-p.projected_amount)/p.projected_amount)*100,4) end variance_percent from keys k left join realized r on r.organization_id=k.organization_id and r.farm_id=k.farm_id and r.crop_season_id is not distinct from k.crop_season_id and r.chart_account_id=k.chart_account_id and r.period_month=k.period_month left join projected p on p.organization_id=k.organization_id and p.farm_id=k.farm_id and p.crop_season_id is not distinct from k.crop_season_id and p.chart_account_id=k.chart_account_id and p.period_month=k.period_month;
