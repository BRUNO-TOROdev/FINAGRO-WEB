-- General allocation is organization-wide and independent from crop seasons.
-- Operation producers are an internal dimension, distinct from counterparties and farms.

alter table public.allocation_rules alter column crop_season_id drop not null;
alter table public.allocation_rules add column allocation_scope text not null default 'SEASONAL';
alter table public.allocation_rules add column effective_from date;
alter table public.allocation_rules add column effective_to date;
alter table public.allocation_rules add constraint allocation_rules_scope_check check(allocation_scope in ('SEASONAL','GENERAL'));
alter table public.allocation_rules add constraint allocation_rules_scope_dimensions_check check(
  (allocation_scope='SEASONAL' and crop_season_id is not null and effective_from is null and effective_to is null)
  or
  (allocation_scope='GENERAL' and crop_season_id is null and effective_from is not null and (effective_to is null or effective_to>=effective_from))
);
alter table public.allocation_rules drop constraint allocation_rules_organization_id_crop_season_id_name_key;
create unique index uq_allocation_rules_seasonal_name on public.allocation_rules(organization_id,crop_season_id,name) where allocation_scope='SEASONAL';
create unique index uq_allocation_rules_general_name_period on public.allocation_rules(organization_id,name,effective_from,coalesce(effective_to,'infinity'::date)) where allocation_scope='GENERAL';
create index idx_allocation_rules_general_resolution on public.allocation_rules(organization_id,effective_from,effective_to) where allocation_scope='GENERAL' and is_active;

create or replace function private.guard_allocation_rule_scope() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and (new.allocation_scope is distinct from old.allocation_scope or new.effective_from is distinct from old.effective_from or new.effective_to is distinct from old.effective_to)
    and exists(select 1 from public.entry_allocations where allocation_rule_id=old.id) then
   raise exception 'USED_ALLOCATION_RULE_IDENTITY_IS_IMMUTABLE';
 end if;
 if new.is_active and new.allocation_scope='GENERAL' and exists(
   select 1 from public.allocation_rules r where r.organization_id=new.organization_id and r.id<>new.id
     and r.allocation_scope='GENERAL' and r.is_active
     and daterange(r.effective_from,coalesce(r.effective_to+1,'infinity'::date),'[)') && daterange(new.effective_from,coalesce(new.effective_to+1,'infinity'::date),'[)')
 ) then raise exception 'GENERAL_ALLOCATION_RULE_PERIOD_OVERLAP'; end if;
 return new;
end$$;
create trigger trg_allocation_rule_scope_guard before insert or update on public.allocation_rules for each row execute function private.guard_allocation_rule_scope();

create or replace function public.resolve_general_allocation_rule(p_organization_id uuid,p_relevant_date date) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid; matches integer;
begin
 if auth.uid() is null or not private.is_org_member(p_organization_id) then raise exception 'PERMISSION_DENIED'; end if;
 select count(*),(array_agg(id order by id))[1] into matches,result from public.allocation_rules
  where organization_id=p_organization_id and allocation_scope='GENERAL' and is_active
    and p_relevant_date>=effective_from and (effective_to is null or p_relevant_date<=effective_to);
 if matches=0 then raise exception 'GENERAL_ALLOCATION_RULE_NOT_FOUND_FOR_DATE'; end if;
 if matches>1 then raise exception 'GENERAL_ALLOCATION_RULE_AMBIGUOUS_FOR_DATE'; end if;
 return result;
end$$;
revoke all on function public.resolve_general_allocation_rule(uuid,date) from public;
grant execute on function public.resolve_general_allocation_rule(uuid,date) to authenticated;

create or replace function public.save_general_allocation_rule(
 p_organization_id uuid,p_rule_id uuid,p_name text,p_description text,p_is_active boolean,
 p_effective_from date,p_effective_to date,p_items jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare target uuid; item_count integer; distinct_farms integer; total numeric(12,6);
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'allocation_rules.manage') then raise exception 'PERMISSION_DENIED'; end if;
 if p_name is null or length(trim(p_name))<2 then raise exception 'ALLOCATION_RULE_NAME_REQUIRED'; end if;
 if p_effective_from is null or (p_effective_to is not null and p_effective_to<p_effective_from) then raise exception 'GENERAL_ALLOCATION_VALIDITY_REQUIRED'; end if;
 if jsonb_typeof(p_items)<>'array' then raise exception 'ALLOCATION_RULE_ITEMS_REQUIRED'; end if;
 select count(*),count(distinct x.farm_id),coalesce(sum(x.percentage),0) into item_count,distinct_farms,total
 from jsonb_to_recordset(p_items) x(farm_id uuid,percentage numeric(9,6));
 if item_count=0 then raise exception 'ALLOCATION_RULE_ITEMS_REQUIRED'; end if;
 if item_count<>distinct_farms then raise exception 'ALLOCATION_RULE_DUPLICATE_FARM'; end if;
 if exists(select 1 from jsonb_to_recordset(p_items)x(farm_id uuid,percentage numeric(9,6)) where x.percentage<=0 or x.percentage>100) then raise exception 'ALLOCATION_RULE_PERCENTAGE_OUT_OF_RANGE'; end if;
 if exists(select 1 from jsonb_to_recordset(p_items)x(farm_id uuid,percentage numeric(9,6)) where not exists(select 1 from public.farms f where f.id=x.farm_id and f.organization_id=p_organization_id and f.is_active)) then raise exception 'FARM_NOT_FOUND_IN_ORGANIZATION'; end if;
 if p_is_active and total<>100.000000 then raise exception 'ALLOCATION_RULE_MUST_TOTAL_100: total %',total; end if;
 if p_rule_id is null then
  insert into public.allocation_rules(organization_id,crop_season_id,name,description,is_active,allocation_scope,effective_from,effective_to)
  values(p_organization_id,null,trim(p_name),nullif(trim(p_description),''),false,'GENERAL',p_effective_from,p_effective_to) returning id into target;
 else
  select id into target from public.allocation_rules where id=p_rule_id and organization_id=p_organization_id and allocation_scope='GENERAL' for update;
  if not found then raise exception 'GENERAL_ALLOCATION_RULE_NOT_FOUND'; end if;
  update public.allocation_rules set name=trim(p_name),description=nullif(trim(p_description),''),is_active=false,effective_from=p_effective_from,effective_to=p_effective_to where id=target;
 end if;
 delete from public.allocation_rule_items where allocation_rule_id=target;
 insert into public.allocation_rule_items(organization_id,allocation_rule_id,farm_id,percentage)
 select p_organization_id,target,x.farm_id,x.percentage from jsonb_to_recordset(p_items)x(farm_id uuid,percentage numeric(9,6));
 update public.allocation_rules set is_active=p_is_active where id=target;
 return target;
end$$;
revoke all on function public.save_general_allocation_rule(uuid,uuid,text,text,boolean,date,date,jsonb) from public;
grant execute on function public.save_general_allocation_rule(uuid,uuid,text,text,boolean,date,date,jsonb) to authenticated;

create table public.operation_producers(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id),
 name text not null,is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(id,organization_id),unique(organization_id,name)
);
alter table public.operation_producers enable row level security;
create policy operation_producers_read on public.operation_producers for select to authenticated using(private.has_permission(organization_id,'entries.view'));
create policy operation_producers_insert on public.operation_producers for insert to authenticated with check(private.has_permission(organization_id,'entries.create'));
create policy operation_producers_update on public.operation_producers for update to authenticated using(private.has_permission(organization_id,'entries.update')) with check(private.has_permission(organization_id,'entries.update'));
grant select,insert,update on public.operation_producers to authenticated;
create trigger trg_operation_producers_updated_at before update on public.operation_producers for each row execute function private.set_updated_at();
create trigger trg_operation_producers_audit after insert or update or delete on public.operation_producers for each row execute function private.audit_row_change();

alter table public.financial_entries add column operation_producer_id uuid;
alter table public.financial_entries add constraint financial_entries_producer_org_fkey foreign key(operation_producer_id,organization_id) references public.operation_producers(id,organization_id);
create index idx_entries_org_producer_issue on public.financial_entries(organization_id,operation_producer_id,issue_date desc) where deleted_at is null;
alter table public.import_staging_rows add column operation_producer_id uuid;
alter table public.import_staging_rows add constraint import_rows_producer_org_fkey foreign key(operation_producer_id,organization_id) references public.operation_producers(id,organization_id);

alter table public.import_mappings drop constraint import_mappings_dimension_check;
alter table public.import_mappings add constraint import_mappings_dimension_check check(dimension in ('FARM','CROP_SEASON','ALLOCATION_RULE','CHART_ACCOUNT','PARTY','PRODUCER','BANK_ACCOUNT','PAYMENT_METHOD','STATUS','DIRECTION'));

create or replace function private.assert_entry_allocation_valid(target_entry uuid) returns void language plpgsql security definer set search_path='' as $$
declare e public.financial_entries%rowtype; total_pct numeric(12,6);total_amount numeric(18,2);allocation_count integer;nonnull_rule_count integer;distinct_rule_count integer;account_allows_allocation boolean;rule_season uuid;rule_scope text;snapshot_missing integer;
begin
 select * into e from public.financial_entries where id=target_entry;
 if not found or e.deleted_at is not null then return; end if;
 select coalesce(sum(a.percentage),0),coalesce(sum(a.allocated_amount),0),count(*),count(a.allocation_rule_id),count(distinct a.allocation_rule_id),
 count(*) filter(where a.allocation_rule_id is not null and a.snapshot_rule_name is null)
 into total_pct,total_amount,allocation_count,nonnull_rule_count,distinct_rule_count,snapshot_missing from public.entry_allocations a where a.financial_entry_id=target_entry;
 if allocation_count=0 then raise exception 'ENTRY_REQUIRES_ALLOCATION: entry %',target_entry; end if;
 if total_pct<>100.000000 then raise exception 'ENTRY_ALLOCATION_PERCENT_MUST_TOTAL_100: entry %, total %',target_entry,total_pct; end if;
 if total_amount<>e.amount then raise exception 'ENTRY_ALLOCATION_AMOUNT_MUST_MATCH_ENTRY: entry %, allocated %, entry amount %',target_entry,total_amount,e.amount; end if;
 if allocation_count>1 and nonnull_rule_count=0 then raise exception 'MULTI_FARM_ALLOCATION_REQUIRES_RULE: entry %',target_entry; end if;
 if nonnull_rule_count>0 then
  if nonnull_rule_count<>allocation_count or distinct_rule_count<>1 then raise exception 'ENTRY_ALLOCATION_CANNOT_MIX_DIRECT_AND_RULE: entry %',target_entry; end if;
  if snapshot_missing>0 then raise exception 'ENTRY_RULE_SNAPSHOT_REQUIRED: entry %',target_entry; end if;
  select r.crop_season_id,r.allocation_scope into rule_season,rule_scope from public.allocation_rules r join public.entry_allocations a on a.allocation_rule_id=r.id where a.financial_entry_id=target_entry limit 1;
  if rule_scope='SEASONAL' and (e.crop_season_id is null or rule_season is distinct from e.crop_season_id) then raise exception 'ALLOCATION_RULE_SEASON_MUST_MATCH_ENTRY_SEASON: entry %',target_entry; end if;
 end if;
 select c.allows_allocation into account_allows_allocation from public.chart_accounts c where c.id=e.chart_account_id;
 if account_allows_allocation is false and allocation_count<>1 then raise exception 'CHART_ACCOUNT_DOES_NOT_ALLOW_MULTI_FARM_ALLOCATION: entry %',target_entry; end if;
end$$;

create or replace function public.apply_allocation_rule(p_financial_entry_id uuid,p_allocation_rule_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare e public.financial_entries%rowtype;r public.allocation_rules%rowtype;season_name text;
begin
 select * into e from public.financial_entries where id=p_financial_entry_id and deleted_at is null for update;if not found then raise exception 'ENTRY_NOT_FOUND';end if;
 if auth.role()<>'service_role' and not(private.has_permission(e.organization_id,'entries.create') or private.has_permission(e.organization_id,'entries.update') or private.has_permission(e.organization_id,'entries.manage_paid')) then raise exception 'PERMISSION_DENIED';end if;
 select * into r from public.allocation_rules where id=p_allocation_rule_id and organization_id=e.organization_id;if not found then raise exception 'ALLOCATION_RULE_NOT_FOUND';end if;
 if not r.is_active then raise exception 'ALLOCATION_RULE_IS_NOT_ACTIVE';end if;
 if r.allocation_scope='SEASONAL' and (e.crop_season_id is null or e.crop_season_id<>r.crop_season_id) then raise exception 'ALLOCATION_RULE_SEASON_MUST_MATCH_ENTRY_SEASON';end if;
 if r.allocation_scope='GENERAL' and (e.issue_date<r.effective_from or (r.effective_to is not null and e.issue_date>r.effective_to)) then raise exception 'GENERAL_ALLOCATION_RULE_NOT_VALID_ON_ENTRY_DATE';end if;
 perform private.assert_allocation_rule_valid(r.id);
 select cs.name into season_name from public.crop_seasons cs where cs.id=r.crop_season_id;
 delete from public.entry_allocations where financial_entry_id=e.id;
 with base as(select i.farm_id,i.percentage,round(e.amount*i.percentage/100.0,2) rounded_amount,row_number()over(order by i.farm_id) rn,count(*)over() cnt from public.allocation_rule_items i where i.allocation_rule_id=r.id),calc as(select b.*,coalesce(sum(b.rounded_amount)over(order by b.rn rows between unbounded preceding and 1 preceding),0)::numeric(18,2) prior_rounded from base b)
 insert into public.entry_allocations(organization_id,financial_entry_id,farm_id,allocation_rule_id,percentage,allocated_amount,snapshot_rule_name,snapshot_crop_season_name)
 select e.organization_id,e.id,c.farm_id,r.id,c.percentage,case when c.rn=c.cnt then e.amount-c.prior_rounded else c.rounded_amount end,r.name,season_name from calc c order by c.rn;
end$$;

-- Recreate the operational RPC, retaining its public signature while accepting GENERAL rules.
create or replace function public.save_financial_entry(
 p_organization_id uuid,p_entry_id uuid,p_entry_direction text,p_status text,p_issue_date date,p_due_date date,p_document_number text,p_document_name text,
 p_description text,p_counterparty_id uuid,p_chart_account_id uuid,p_crop_season_id uuid,p_payment_method_id uuid,p_planned_bank_account_id uuid,
 p_amount numeric,p_notes text,p_allocation_mode text,p_farm_id uuid,p_allocation_rule_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare target_id uuid;old_entry public.financial_entries%rowtype;prior_count integer:=0;prior_farm uuid;prior_rule uuid;allocation_changed boolean:=true;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if p_entry_direction not in('ENTRADA','SAIDA') then raise exception 'INVALID_ENTRY_DIRECTION';end if;
 if p_status not in('PENDENTE','AGENDADO') then raise exception 'MANUAL_ENTRY_STATUS_MUST_BE_PENDING_OR_SCHEDULED';end if;
 if p_amount is null or p_amount<=0 then raise exception 'FINANCIAL_ENTRY_AMOUNT_MUST_BE_POSITIVE';end if;
 if p_issue_date is null or p_due_date is null then raise exception 'ENTRY_DATES_REQUIRED';end if;
 if p_description is null or length(trim(p_description))<2 then raise exception 'ENTRY_DESCRIPTION_REQUIRED';end if;
 if p_allocation_mode not in('DIRETA','RATEIO') then raise exception 'INVALID_ALLOCATION_MODE';end if;
 if p_entry_id is null then if not private.has_permission(p_organization_id,'entries.create') then raise exception 'PERMISSION_DENIED';end if;
 else
  if not private.has_permission(p_organization_id,'entries.update') then raise exception 'PERMISSION_DENIED';end if;
  select * into old_entry from public.financial_entries where id=p_entry_id and organization_id=p_organization_id and deleted_at is null for update;if not found then raise exception 'FINANCIAL_ENTRY_NOT_FOUND';end if;
  if old_entry.status='PAGO' then raise exception 'PAID_ENTRY_IS_READ_ONLY';end if;
  if exists(select 1 from public.settlements where financial_entry_id=p_entry_id and reversed_at is null) then raise exception 'ENTRY_WITH_SETTLEMENT_IS_READ_ONLY';end if;
  select count(*),(array_agg(a.farm_id order by a.farm_id))[1],(array_agg(a.allocation_rule_id order by a.allocation_rule_id)filter(where a.allocation_rule_id is not null))[1] into prior_count,prior_farm,prior_rule from public.entry_allocations a where a.financial_entry_id=p_entry_id;
  allocation_changed:=old_entry.amount is distinct from p_amount or (p_allocation_mode='DIRETA' and(prior_count<>1 or prior_rule is not null or prior_farm is distinct from p_farm_id)) or(p_allocation_mode='RATEIO' and(prior_count=0 or prior_rule is distinct from p_allocation_rule_id));
 end if;
 if not exists(select 1 from public.chart_accounts c where c.id=p_chart_account_id and c.organization_id=p_organization_id and(c.is_active or(p_entry_id is not null and c.id=old_entry.chart_account_id))) then raise exception 'ACTIVE_CHART_ACCOUNT_NOT_FOUND_IN_ORGANIZATION';end if;
 if p_crop_season_id is not null and not exists(select 1 from public.crop_seasons where id=p_crop_season_id and organization_id=p_organization_id) then raise exception 'CROP_SEASON_NOT_FOUND_IN_ORGANIZATION';end if;
 if p_counterparty_id is not null and not exists(select 1 from public.parties p where p.id=p_counterparty_id and p.organization_id=p_organization_id and(p.is_active or(p_entry_id is not null and p.id=old_entry.counterparty_id))) then raise exception 'ACTIVE_COUNTERPARTY_NOT_FOUND_IN_ORGANIZATION';end if;
 if p_planned_bank_account_id is not null and not exists(select 1 from public.bank_accounts b where b.id=p_planned_bank_account_id and b.organization_id=p_organization_id and(b.is_active or(p_entry_id is not null and b.id=old_entry.planned_bank_account_id))) then raise exception 'ACTIVE_BANK_ACCOUNT_NOT_FOUND_IN_ORGANIZATION';end if;
 if p_payment_method_id is not null and not exists(select 1 from public.payment_methods m where m.id=p_payment_method_id and m.organization_id=p_organization_id and(m.is_active or(p_entry_id is not null and m.id=old_entry.payment_method_id))) then raise exception 'ACTIVE_PAYMENT_METHOD_NOT_FOUND_IN_ORGANIZATION';end if;
 if p_allocation_mode='DIRETA' then
  if p_farm_id is null or p_allocation_rule_id is not null then raise exception 'DIRECT_ALLOCATION_REQUIRES_ONE_FARM';end if;
  if not exists(select 1 from public.farms where id=p_farm_id and organization_id=p_organization_id and is_active) then raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION';end if;
 else
  if p_allocation_rule_id is null or p_farm_id is not null then raise exception 'RULE_ALLOCATION_REQUIRES_ONE_RULE';end if;
  if exists(select 1 from public.allocation_rules r where r.id=p_allocation_rule_id and r.organization_id=p_organization_id and r.allocation_scope='SEASONAL') and not exists(select 1 from public.allocation_rules r where r.id=p_allocation_rule_id and r.organization_id=p_organization_id and r.is_active and r.crop_season_id=p_crop_season_id) then raise exception 'ACTIVE_ALLOCATION_RULE_MUST_MATCH_ENTRY_SEASON';end if;
  if exists(select 1 from public.allocation_rules r where r.id=p_allocation_rule_id and r.organization_id=p_organization_id and r.allocation_scope='GENERAL') and not exists(select 1 from public.allocation_rules r where r.id=p_allocation_rule_id and r.organization_id=p_organization_id and r.is_active and p_issue_date>=r.effective_from and(r.effective_to is null or p_issue_date<=r.effective_to)) then raise exception 'GENERAL_ALLOCATION_RULE_NOT_VALID_ON_ENTRY_DATE';end if;
  if not exists(select 1 from public.allocation_rules r where r.id=p_allocation_rule_id and r.organization_id=p_organization_id) then raise exception 'ALLOCATION_RULE_NOT_FOUND';end if;
 end if;
 if p_entry_id is null then
  insert into public.financial_entries(organization_id,entry_direction,status,issue_date,due_date,document_number,document_name,description,counterparty_id,chart_account_id,crop_season_id,payment_method_id,planned_bank_account_id,amount,source_type,notes,created_by,updated_by)
  values(p_organization_id,p_entry_direction,p_status,p_issue_date,p_due_date,nullif(trim(p_document_number),''),nullif(trim(p_document_name),''),trim(p_description),p_counterparty_id,p_chart_account_id,p_crop_season_id,p_payment_method_id,p_planned_bank_account_id,p_amount,'MANUAL',nullif(trim(p_notes),''),auth.uid(),auth.uid()) returning id into target_id;
 else
  target_id:=p_entry_id;update public.financial_entries set entry_direction=p_entry_direction,status=p_status,issue_date=p_issue_date,due_date=p_due_date,document_number=nullif(trim(p_document_number),''),document_name=nullif(trim(p_document_name),''),description=trim(p_description),counterparty_id=p_counterparty_id,chart_account_id=p_chart_account_id,crop_season_id=p_crop_season_id,payment_method_id=p_payment_method_id,planned_bank_account_id=p_planned_bank_account_id,amount=p_amount,notes=nullif(trim(p_notes),''),updated_by=auth.uid() where id=target_id;
 end if;
 if p_entry_id is null or allocation_changed then if p_allocation_mode='DIRETA' then perform public.apply_direct_farm_allocation(target_id,p_farm_id);else perform public.apply_allocation_rule(target_id,p_allocation_rule_id);end if;end if;
 return target_id;
end$$;

-- GENERAL allocation is independent from analytical season in budgets.
create or replace function private.rebuild_budget_item_allocations(p_item_id uuid,p_organization_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare item public.budget_items%rowtype;r record;remaining numeric(18,2);part numeric(18,2);rule_name text;
begin
 select * into item from public.budget_items where id=p_item_id and organization_id=p_organization_id;if not found then raise exception 'BUDGET_ITEM_NOT_FOUND';end if;
 delete from public.budget_item_allocations where budget_item_id=item.id and organization_id=item.organization_id;
 if item.direct_farm_id is not null then if not exists(select 1 from public.farms where id=item.direct_farm_id and organization_id=item.organization_id and is_active) then raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION';end if;insert into public.budget_item_allocations(organization_id,budget_item_id,farm_id,percentage,allocated_amount)values(item.organization_id,item.id,item.direct_farm_id,100,item.amount);return;end if;
 select name into rule_name from public.allocation_rules where id=item.allocation_rule_id and organization_id=item.organization_id and is_active and ((allocation_scope='GENERAL' and item.period_month>=effective_from and(effective_to is null or item.period_month<=effective_to))or(allocation_scope='SEASONAL' and crop_season_id is not distinct from item.crop_season_id));
 if rule_name is null then raise exception 'ACTIVE_ALLOCATION_RULE_NOT_VALID_FOR_BUDGET_PERIOD';end if;
 remaining=item.amount;for r in select ri.*,row_number()over(order by ri.farm_id)n,count(*)over()total from public.allocation_rule_items ri where ri.allocation_rule_id=item.allocation_rule_id and ri.organization_id=item.organization_id order by ri.farm_id loop part=case when r.n=r.total then remaining else round(item.amount*r.percentage/100,2)end;remaining=remaining-part;insert into public.budget_item_allocations(organization_id,budget_item_id,farm_id,allocation_rule_id,percentage,allocated_amount,snapshot_rule_name)values(item.organization_id,item.id,r.farm_id,item.allocation_rule_id,r.percentage,part,rule_name);end loop;
 if remaining<>0 or(select coalesce(sum(percentage),0)from public.budget_item_allocations where budget_item_id=item.id)<>100 or(select coalesce(sum(allocated_amount),0)from public.budget_item_allocations where budget_item_id=item.id)<>item.amount then raise exception 'BUDGET_ALLOCATION_MUST_MATCH_ITEM';end if;
end$$;

-- Import v3: safe trimmed account matching, date-effective GENERAL and separate external party/producer mappings.
alter function public.analyze_finagro_import(uuid,text,text,date,date,jsonb) rename to analyze_finagro_import_v2;
revoke all on function public.analyze_finagro_import_v2(uuid,text,text,date,date,jsonb) from public,authenticated;
create or replace function public.analyze_finagro_import(p_organization_id uuid,p_file_name text,p_file_sha256 text,p_period_start date,p_period_end date,p_rows jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare b uuid;r jsonb;n int;issues jsonb;transforms jsonb;account_id uuid;account_matches int;farm_target uuid;season_target uuid;rule_target uuid;rule_matches int;party_target uuid;producer_target uuid;bank_target uuid;method_target uuid;normalized_s text;normalized_d text;amount_v numeric;issue_d date;due_d date;resolution text;group_v text;subgroup_v text;farm_v text;season_v text;status_v text;direction_v text;party_name text;party_doc text;producer_name text;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'imports.execute') then raise exception 'PERMISSION_DENIED';end if;
 if p_period_start is null or p_period_end is null or p_period_end<p_period_start then raise exception 'CLOSED_IMPORT_PERIOD_REQUIRED';end if;
 if jsonb_typeof(p_rows)<>'array' then raise exception 'IMPORT_ROWS_ARRAY_REQUIRED';end if;
 insert into public.import_batches(organization_id,source_file_name,source_file_sha256,period_start,period_end,total_rows,created_by)values(p_organization_id,p_file_name,p_file_sha256,p_period_start,p_period_end,jsonb_array_length(p_rows),auth.uid())returning id into b;
 for r in select value from jsonb_array_elements(p_rows) loop
  n=(r->>'source_row_number')::int;issues='[]';transforms='[]';resolution='VALID';account_id=null;farm_target=null;season_target=null;rule_target=null;party_target=null;producer_target=null;bank_target=null;method_target=null;
  group_v=nullif(trim(r->>'group'),'');subgroup_v=nullif(trim(r->>'subgroup'),'');farm_v=nullif(trim(r->>'farm'),'');season_v=nullif(trim(r->>'season'),'');status_v=upper(nullif(trim(r->>'status'),''));direction_v=upper(nullif(trim(r->>'direction'),''));party_name=nullif(trim(r->>'document_name'),'');party_doc=nullif(trim(r->>'client'),'');producer_name=nullif(trim(r->>'producer'),'');
  begin issue_d=(r->>'issue_date')::date;exception when others then issue_d=null;end;begin due_d=(r->>'due_date')::date;exception when others then due_d=null;end;begin amount_v=(r->>'amount')::numeric;exception when others then amount_v=null;end;
  if issue_d is null or due_d is null or issue_d<p_period_start or issue_d>p_period_end then issues=issues||jsonb_build_array(jsonb_build_object('code','INVALID_OR_OUTSIDE_ISSUE_DATE','severity','BLOCKED'));end if;if amount_v is null or amount_v<=0 then issues=issues||jsonb_build_array(jsonb_build_object('code','INVALID_AMOUNT','severity','BLOCKED'));end if;
  normalized_s=case coalesce((select upper(m.target_value)from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='STATUS' and upper(m.source_value)=status_v),status_v)when'PENDENTE'then'PENDENTE'when'AGENDADO'then'AGENDADO'when'PAGO'then'PENDENTE'end;
  if normalized_s is null then issues=issues||jsonb_build_array(jsonb_build_object('code','UNRECOGNIZED_STATUS','severity','BLOCKED','source',status_v));end if;
  normalized_d=case coalesce((select upper(m.target_value)from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='DIRECTION' and upper(m.source_value)=direction_v),direction_v)when'E'then'ENTRADA'when'S'then'SAIDA'when'ENTRADA'then'ENTRADA'when'SAIDA'then'SAIDA'end;if normalized_d is null then issues=issues||jsonb_build_array(jsonb_build_object('code','UNRECOGNIZED_DIRECTION','severity','BLOCKED'));end if;
  select count(*),(array_agg(c.id order by c.id))[1]into account_matches,account_id from public.chart_accounts c join public.chart_accounts p on p.id=c.parent_id and p.organization_id=c.organization_id where c.organization_id=p_organization_id and c.is_active and btrim(c.source_name)=subgroup_v and btrim(p.source_name)=group_v;
  if account_matches>1 then account_id=null;issues=issues||jsonb_build_array(jsonb_build_object('code','CHART_ACCOUNT_TRIM_MATCH_AMBIGUOUS','severity','BLOCKED'));elsif account_matches=1 then transforms=transforms||jsonb_build_array(jsonb_build_object('field','chart_account','rule',case when exists(select 1 from public.chart_accounts c join public.chart_accounts p on p.id=c.parent_id where c.id=account_id and c.source_name=subgroup_v and p.source_name=group_v)then'EXACT_SOURCE_NAME'else'TRIM_EXACT_UNAMBIGUOUS'end,'source_group',r->>'group','source_subgroup',r->>'subgroup','target_id',account_id));end if;
  if account_id is null and account_matches=0 then select m.target_id into account_id from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='CHART_ACCOUNT' and m.source_value=coalesce(group_v,'')and m.secondary_source_value=coalesce(subgroup_v,'');end if;if account_id is null and account_matches<>2 then issues=issues||jsonb_build_array(jsonb_build_object('code','CHART_ACCOUNT_NOT_FOUND','severity','BLOCKED'));end if;
  select s.id into season_target from public.crop_seasons s where s.organization_id=p_organization_id and upper(s.name)=upper(season_v)limit 1;if season_target is null then select m.target_id into season_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='CROP_SEASON' and upper(m.source_value)=upper(coalesce(season_v,''));end if;if season_v is not null and season_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','CROP_SEASON_NOT_FOUND','severity','BLOCKED'));end if;
  if upper(coalesce(farm_v,''))='GERAL' then select count(*),(array_agg(id order by id))[1]into rule_matches,rule_target from public.allocation_rules where organization_id=p_organization_id and allocation_scope='GENERAL' and is_active and issue_d>=effective_from and(effective_to is null or issue_d<=effective_to);if rule_matches=0 then issues=issues||jsonb_build_array(jsonb_build_object('code','GENERAL_ALLOCATION_RULE_NOT_FOUND_FOR_DATE','severity','BLOCKED'));elsif rule_matches>1 then rule_target=null;issues=issues||jsonb_build_array(jsonb_build_object('code','GENERAL_ALLOCATION_RULE_AMBIGUOUS_FOR_DATE','severity','BLOCKED'));else transforms=transforms||jsonb_build_array(jsonb_build_object('field','allocation_rule','rule','GENERAL_BY_ISSUE_DATE','target_id',rule_target));end if;
  else select f.id into farm_target from public.farms f where f.organization_id=p_organization_id and f.is_active and(upper(f.name)=upper(farm_v)or upper(coalesce(f.internal_code,''))=upper(farm_v))limit 1;if farm_target is null then select m.target_id into farm_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='FARM' and upper(m.source_value)=upper(coalesce(farm_v,''));end if;if farm_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','FARM_NOT_FOUND','severity','BLOCKED'));end if;end if;
  select m.target_id into party_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='PARTY' and m.source_value=coalesce(party_name,'')and m.secondary_source_value=coalesce(party_doc,'');if party_name is not null and party_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','EXTERNAL_COUNTERPARTY_MAPPING_REQUIRED','severity','BLOCKED'));end if;
  select m.target_id into producer_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='PRODUCER' and m.source_value=coalesce(producer_name,'');if producer_name is not null and producer_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','OPERATION_PRODUCER_MAPPING_REQUIRED','severity','BLOCKED'));end if;
  select m.target_id into bank_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='BANK_ACCOUNT' and m.source_value=coalesce(r->>'bank','')and m.secondary_source_value=coalesce(r->>'bank_account','');if(nullif(trim(r->>'bank'),'')is not null or nullif(trim(r->>'bank_account'),'')is not null)and bank_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','BANK_ACCOUNT_NOT_FOUND','severity','BLOCKED'));end if;
  select m.target_id into method_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='PAYMENT_METHOD' and m.source_value=coalesce(r->>'payment_method','');
  if status_v='PAGO' then if due_d is null then issues=issues||jsonb_build_array(jsonb_build_object('code','HISTORICAL_SETTLEMENT_REFERENCE_DATE_REQUIRED','severity','BLOCKED'));end if;if bank_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','HISTORICAL_PAID_BANK_ACCOUNT_REQUIRED','severity','BLOCKED'));end if;transforms=transforms||jsonb_build_array(jsonb_build_object('field','settlement_date','source','due_date','target',due_d,'rule','DUE_DATE_SURROGATE_NOT_BANK_CONFIRMED'));end if;
  if exists(select 1 from jsonb_array_elements(issues)x where x->>'severity'='BLOCKED')then resolution='BLOCKED';elsif jsonb_array_length(issues)>0 then resolution='WARNING';end if;
  insert into public.import_staging_rows(organization_id,import_batch_id,source_row_number,source_row_hash,source_data,issue_date,due_date,source_group,source_subgroup,source_farm,source_season,source_status,source_direction,amount,chart_account_id,farm_id,crop_season_id,allocation_rule_id,counterparty_id,operation_producer_id,bank_account_id,payment_method_id,normalized_status,normalized_direction,resolution_status,issues,transformations)
  values(p_organization_id,b,n,pg_catalog.md5(p_file_sha256||':'||n::text),r,issue_d,due_d,group_v,subgroup_v,farm_v,season_v,status_v,direction_v,amount_v,account_id,farm_target,season_target,rule_target,party_target,producer_target,bank_target,method_target,normalized_s,normalized_d,resolution,issues,transforms);
 end loop;
 update public.import_batches set valid_rows=(select count(*)from public.import_staging_rows where import_batch_id=b and resolution_status='VALID'),warning_rows=(select count(*)from public.import_staging_rows where import_batch_id=b and resolution_status='WARNING'),blocked_rows=(select count(*)from public.import_staging_rows where import_batch_id=b and resolution_status='BLOCKED')where id=b;
 insert into public.audit_logs(organization_id,actor_user_id,entity_type,entity_id,action,new_data)values(p_organization_id,auth.uid(),'IMPORT_BATCH',b,'IMPORT_ANALYZED',jsonb_build_object('dry_run',true,'row_count',jsonb_array_length(p_rows),'general_resolution','ISSUE_DATE','producer_dimension',true));return b;
end$$;
revoke all on function public.analyze_finagro_import(uuid,text,text,date,date,jsonb) from public;grant execute on function public.analyze_finagro_import(uuid,text,text,date,date,jsonb) to authenticated;

-- Extend explicit mappings with producer validation while retaining every prior dimension.
create or replace function public.save_import_mapping(p_organization_id uuid,p_dimension text,p_source_value text,p_secondary_source_value text,p_target_id uuid,p_target_value text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'imports.execute')then raise exception 'PERMISSION_DENIED';end if;
 if p_dimension not in('FARM','CROP_SEASON','ALLOCATION_RULE','CHART_ACCOUNT','PARTY','PRODUCER','BANK_ACCOUNT','PAYMENT_METHOD','STATUS','DIRECTION')then raise exception 'INVALID_IMPORT_MAPPING_DIMENSION';end if;
 if p_dimension='STATUS' and upper(coalesce(p_target_value,''))not in('PENDENTE','AGENDADO')then raise exception 'INVALID_IMPORT_STATUS_TARGET';end if;if p_dimension='DIRECTION' and upper(coalesce(p_target_value,''))not in('ENTRADA','SAIDA')then raise exception 'INVALID_IMPORT_DIRECTION_TARGET';end if;
 if p_target_id is not null and(case p_dimension when'FARM'then not exists(select 1 from public.farms where id=p_target_id and organization_id=p_organization_id)when'CROP_SEASON'then not exists(select 1 from public.crop_seasons where id=p_target_id and organization_id=p_organization_id)when'ALLOCATION_RULE'then not exists(select 1 from public.allocation_rules where id=p_target_id and organization_id=p_organization_id)when'CHART_ACCOUNT'then not exists(select 1 from public.chart_accounts where id=p_target_id and organization_id=p_organization_id)when'PARTY'then not exists(select 1 from public.parties where id=p_target_id and organization_id=p_organization_id)when'PRODUCER'then not exists(select 1 from public.operation_producers where id=p_target_id and organization_id=p_organization_id)when'BANK_ACCOUNT'then not exists(select 1 from public.bank_accounts where id=p_target_id and organization_id=p_organization_id)when'PAYMENT_METHOD'then not exists(select 1 from public.payment_methods where id=p_target_id and organization_id=p_organization_id)else false end)then raise exception 'IMPORT_MAPPING_TARGET_NOT_FOUND_IN_ORGANIZATION';end if;
 insert into public.import_mappings(organization_id,dimension,source_value,secondary_source_value,target_id,target_value,created_by)values(p_organization_id,p_dimension,trim(p_source_value),coalesce(trim(p_secondary_source_value),''),p_target_id,p_target_value,auth.uid())on conflict(organization_id,dimension,source_value,secondary_source_value)do update set target_id=excluded.target_id,target_value=excluded.target_value,created_by=auth.uid(),created_at=now()returning id into result;return result;
end$$;

-- Confirmation retains historical settlement provenance and adds the independent producer link.
create or replace function public.confirm_finagro_import(p_organization_id uuid,p_batch_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare r record;entry_id uuid;settlement_id uuid;imported int:=0;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'imports.execute')then raise exception 'PERMISSION_DENIED';end if;if not exists(select 1 from public.import_batches where id=p_batch_id and organization_id=p_organization_id and status='ANALISADO' and blocked_rows=0)then raise exception 'IMPORT_BATCH_NOT_READY';end if;
 for r in select * from public.import_staging_rows where import_batch_id=p_batch_id and organization_id=p_organization_id and resolution_status in('VALID','WARNING')order by source_row_number loop
  entry_id=public.save_financial_entry(p_organization_id,null,r.normalized_direction,r.normalized_status,r.issue_date,r.due_date,r.source_data->>'document_number',r.source_data->>'document_name',coalesce(nullif(r.source_data->>'description',''),'Importação FINAGRO'),r.counterparty_id,r.chart_account_id,r.crop_season_id,r.payment_method_id,r.bank_account_id,r.amount,format('Import batch %s, linha %s',p_batch_id,r.source_row_number),case when r.allocation_rule_id is null then'DIRETA'else'RATEIO'end,r.farm_id,r.allocation_rule_id);
  update public.financial_entries set source_type='IMPORTACAO',operation_producer_id=r.operation_producer_id where id=entry_id;
  if r.source_status='PAGO' then if r.due_date is null or r.bank_account_id is null then raise exception 'HISTORICAL_PAID_ROW_NOT_READY';end if;insert into public.settlements(organization_id,financial_entry_id,bank_account_id,payment_method_id,settled_at,amount,reference,notes,created_by,date_basis,import_batch_id,import_staging_row_id)values(p_organization_id,entry_id,r.bank_account_id,r.payment_method_id,r.due_date::timestamptz,r.amount,'Migração histórica FINAGRO','Data de vencimento usada como substituta técnica; não confirma a data bancária.',auth.uid(),'DUE_DATE_SURROGATE',p_batch_id,r.id)returning id into settlement_id;end if;
  update public.import_staging_rows set financial_entry_id=entry_id,historical_settlement_id=settlement_id,resolution_status='IMPORTED'where id=r.id;settlement_id=null;imported=imported+1;
 end loop;update public.import_batches set status='CONFIRMADO',is_dry_run=false,confirmed_by=auth.uid(),confirmed_at=now()where id=p_batch_id;insert into public.audit_logs(organization_id,actor_user_id,entity_type,entity_id,action,new_data)values(p_organization_id,auth.uid(),'IMPORT_BATCH',p_batch_id,'IMPORT_CONFIRMED',jsonb_build_object('created_entries',imported,'historical_paid_date_basis','DUE_DATE_SURROGATE','producer_dimension',true));return imported;
end$$;
revoke all on function public.confirm_finagro_import(uuid,uuid) from public;grant execute on function public.confirm_finagro_import(uuid,uuid) to authenticated;

revoke all on function private.guard_allocation_rule_scope(),private.assert_entry_allocation_valid(uuid),private.rebuild_budget_item_allocations(uuid,uuid) from public,authenticated;

-- Keep the established financing and budget RPC signatures, replacing only their
-- season-coupling predicates. GENERAL is validated by scope/date; SEASONAL keeps
-- the original crop-season coherence.
create or replace function private.guard_financing_contract() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then raise exception 'FINANCING_ORGANIZATION_IS_IMMUTABLE';end if;
 if new.allocation_rule_id is not null and not exists(select 1 from public.allocation_rules r where r.id=new.allocation_rule_id and r.organization_id=new.organization_id and r.is_active and ((r.allocation_scope='GENERAL' and new.issued_on>=r.effective_from and(r.effective_to is null or new.issued_on<=r.effective_to))or(r.allocation_scope='SEASONAL' and r.crop_season_id=new.crop_season_id)))then raise exception 'ACTIVE_ALLOCATION_RULE_NOT_VALID_FOR_FINANCING';end if;
 if new.farm_id is not null and not exists(select 1 from public.farms f where f.id=new.farm_id and f.organization_id=new.organization_id and f.is_active)then raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION';end if;
 if tg_op='UPDATE' and(old.credit_entry_id is not null or exists(select 1 from public.financing_installments i where i.financing_contract_id=old.id))and(new.contract_number is distinct from old.contract_number or new.contracted_amount is distinct from old.contracted_amount or new.installment_count is distinct from old.installment_count or new.creditor_party_id is distinct from old.creditor_party_id or new.bank_account_id is distinct from old.bank_account_id or new.crop_season_id is distinct from old.crop_season_id or new.farm_id is distinct from old.farm_id or new.allocation_rule_id is distinct from old.allocation_rule_id)then raise exception 'FINANCING_CONTRACT_WITH_MOVEMENTS_IS_IMMUTABLE';end if;return new;
end$$;

do $$declare definition text;begin
 select pg_get_functiondef('public.create_financing_contract_with_schedule(uuid,uuid,text,text,numeric,date,date,integer,uuid,uuid,uuid,uuid,text,numeric,text,text,text,boolean,date,text,numeric,uuid,uuid,uuid,uuid,boolean,jsonb)'::regprocedure)into definition;
 definition=replace(definition,'r.crop_season_id=p_crop_season_id','((r.allocation_scope=''GENERAL'' and p_issued_on>=r.effective_from and (r.effective_to is null or p_issued_on<=r.effective_to)) or (r.allocation_scope=''SEASONAL'' and r.crop_season_id=p_crop_season_id))');
 if position('allocation_scope' in definition)=0 then raise exception 'FINANCING_GENERAL_PATCH_NOT_APPLIED';end if;
 execute definition;
end$$;

do $$declare definition text;begin
 select pg_get_functiondef('public.replace_budget_projection_items(uuid,uuid,text,jsonb)'::regprocedure)into definition;
 definition=replace(definition,'crop_season_id is not distinct from coalesce(season_id,plan.crop_season_id)','((allocation_scope=''GENERAL'' and month_date>=effective_from and (effective_to is null or month_date<=effective_to)) or (allocation_scope=''SEASONAL'' and crop_season_id is not distinct from coalesce(season_id,plan.crop_season_id)))');
 if position('allocation_scope' in definition)=0 then raise exception 'BUDGET_REPLACE_GENERAL_PATCH_NOT_APPLIED';end if;
 execute definition;
 select pg_get_functiondef('public.save_budget_projection_series(uuid,uuid,text,uuid,uuid,uuid,uuid,jsonb)'::regprocedure)into definition;
 definition=replace(definition,'crop_season_id is not distinct from coalesce(p_crop_season_id,plan.crop_season_id)','((allocation_scope=''GENERAL'' and plan.starts_on>=effective_from and (effective_to is null or plan.starts_on<=effective_to)) or (allocation_scope=''SEASONAL'' and crop_season_id is not distinct from coalesce(p_crop_season_id,plan.crop_season_id)))');
 if position('allocation_scope' in definition)=0 then raise exception 'BUDGET_SERIES_GENERAL_PATCH_NOT_APPLIED';end if;
 execute definition;
end$$;
