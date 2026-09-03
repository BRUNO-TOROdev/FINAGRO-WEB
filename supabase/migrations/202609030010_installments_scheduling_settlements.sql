-- FINAGRO Web — installments, scheduling and settlements operational cycle.
-- Additive only: migrations 001–009 remain immutable.

alter table public.settlements add column payment_method_id uuid;
alter table public.settlements add constraint settlements_payment_method_org_fkey
  foreign key (payment_method_id,organization_id) references public.payment_methods(id,organization_id);
create index idx_entries_org_installment_plan on public.financial_entries(organization_id,installment_plan_id,installment_number) where installment_plan_id is not null and deleted_at is null;
create index idx_settlements_org_entry_active on public.settlements(organization_id,financial_entry_id,settled_at) where reversed_at is null;

create or replace function private.guard_settlement_insert() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.financial_entries e where e.id=new.financial_entry_id and e.organization_id=new.organization_id and e.deleted_at is null) then raise exception 'ACTIVE_FINANCIAL_ENTRY_REQUIRED_FOR_SETTLEMENT'; end if;
  if exists(select 1 from public.bank_accounts b where b.id=new.bank_account_id and b.organization_id=new.organization_id and not b.is_active)
     or not exists(select 1 from public.bank_accounts b where b.id=new.bank_account_id) then raise exception 'ACTIVE_BANK_ACCOUNT_NOT_FOUND_IN_ORGANIZATION'; end if;
  if new.payment_method_id is not null and (exists(select 1 from public.payment_methods p where p.id=new.payment_method_id and p.organization_id=new.organization_id and not p.is_active)
     or not exists(select 1 from public.payment_methods p where p.id=new.payment_method_id)) then raise exception 'ACTIVE_PAYMENT_METHOD_NOT_FOUND_IN_ORGANIZATION'; end if;
  if auth.role()<>'service_role' then
    if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
    if new.created_by is not null and new.created_by<>auth.uid() then raise exception 'SETTLEMENT_CREATED_BY_MUST_MATCH_CALLER'; end if;
    new.created_by:=auth.uid();
  end if;
  return new;
end$$;

create or replace function private.guard_settlement_update() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.reversed_at is not null then raise exception 'REVERSED_SETTLEMENT_IS_IMMUTABLE'; end if;
  if new.organization_id is distinct from old.organization_id or new.financial_entry_id is distinct from old.financial_entry_id
    or new.bank_account_id is distinct from old.bank_account_id or new.payment_method_id is distinct from old.payment_method_id
    or new.settled_at is distinct from old.settled_at or new.amount is distinct from old.amount
    or new.reference is distinct from old.reference or new.notes is distinct from old.notes
    or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at
  then raise exception 'SETTLEMENT_CORRECTION_REQUIRES_REVERSAL'; end if;
  if new.reversed_at is null then raise exception 'SETTLEMENT_UPDATE_ONLY_ALLOWED_FOR_REVERSAL'; end if;
  if new.reversed_by is null or new.reversal_reason is null or length(trim(new.reversal_reason))=0 then raise exception 'SETTLEMENT_REVERSAL_REQUIRES_USER_AND_REASON'; end if;
  return new;
end$$;

create or replace function public.create_settlement(p_organization_id uuid,p_financial_entry_id uuid,p_bank_account_id uuid,p_payment_method_id uuid,p_settled_at timestamptz,p_amount numeric,p_reference text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; entry_amount numeric; active_total numeric;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if not private.has_permission(p_organization_id,'settlements.create') then raise exception 'PERMISSION_DENIED'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'SETTLEMENT_AMOUNT_MUST_BE_POSITIVE'; end if;
  if p_settled_at is null then raise exception 'SETTLEMENT_DATE_REQUIRED'; end if;
  select e.amount into entry_amount from public.financial_entries e where e.id=p_financial_entry_id and e.organization_id=p_organization_id and e.deleted_at is null for update;
  if not found then raise exception 'FINANCIAL_ENTRY_NOT_FOUND'; end if;
  if not exists(select 1 from public.bank_accounts b where b.id=p_bank_account_id and b.organization_id=p_organization_id and b.is_active) then raise exception 'ACTIVE_BANK_ACCOUNT_NOT_FOUND_IN_ORGANIZATION'; end if;
  if p_payment_method_id is not null and not exists(select 1 from public.payment_methods p where p.id=p_payment_method_id and p.organization_id=p_organization_id and p.is_active) then raise exception 'ACTIVE_PAYMENT_METHOD_NOT_FOUND_IN_ORGANIZATION'; end if;
  select coalesce(sum(s.amount),0) into active_total from public.settlements s where s.financial_entry_id=p_financial_entry_id and s.reversed_at is null;
  if active_total+p_amount>entry_amount then raise exception 'SETTLEMENTS_CANNOT_EXCEED_ENTRY_AMOUNT'; end if;
  insert into public.settlements(organization_id,financial_entry_id,bank_account_id,payment_method_id,settled_at,amount,reference,notes,created_by)
  values(p_organization_id,p_financial_entry_id,p_bank_account_id,p_payment_method_id,p_settled_at,p_amount,nullif(trim(p_reference),''),nullif(trim(p_notes),''),auth.uid()) returning id into result;
  return result;
end$$;
revoke all on function public.create_settlement(uuid,uuid,uuid,uuid,timestamptz,numeric,text,text) from public;
grant execute on function public.create_settlement(uuid,uuid,uuid,uuid,timestamptz,numeric,text,text) to authenticated;

create or replace function public.set_financial_entry_schedule_status(p_organization_id uuid,p_financial_entry_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
declare current_status text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if not private.has_permission(p_organization_id,'entries.update') then raise exception 'PERMISSION_DENIED'; end if;
  if p_status not in ('PENDENTE','AGENDADO') then raise exception 'SCHEDULE_STATUS_MUST_BE_PENDING_OR_SCHEDULED'; end if;
  select status into current_status from public.financial_entries where id=p_financial_entry_id and organization_id=p_organization_id and deleted_at is null for update;
  if not found then raise exception 'FINANCIAL_ENTRY_NOT_FOUND'; end if;
  if current_status='PAGO' then raise exception 'PAID_ENTRY_STATUS_IS_DERIVED'; end if;
  update public.financial_entries set status=p_status,updated_by=auth.uid() where id=p_financial_entry_id;
end$$;
revoke all on function public.set_financial_entry_schedule_status(uuid,uuid,text) from public;
grant execute on function public.set_financial_entry_schedule_status(uuid,uuid,text) to authenticated;

create or replace function public.create_installment_plan(
 p_organization_id uuid,p_description text,p_total_amount numeric,p_issue_date date,p_entry_direction text,
 p_counterparty_id uuid,p_chart_account_id uuid,p_crop_season_id uuid,p_payment_method_id uuid,p_planned_bank_account_id uuid,
 p_document_number text,p_document_name text,p_notes text,p_allocation_mode text,p_farm_id uuid,p_allocation_rule_id uuid,p_installments jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare plan_id uuid; item jsonb; item_count int; amount_sum numeric; entry_id uuid; expected_number int:=1;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if not private.has_permission(p_organization_id,'entries.create') then raise exception 'PERMISSION_DENIED'; end if;
 if p_total_amount is null or p_total_amount<=0 then raise exception 'INSTALLMENT_PLAN_AMOUNT_MUST_BE_POSITIVE'; end if;
 if jsonb_typeof(p_installments)<>'array' then raise exception 'INSTALLMENTS_MUST_BE_ARRAY'; end if;
 select count(*),coalesce(sum((x->>'amount')::numeric),0) into item_count,amount_sum from jsonb_array_elements(p_installments) x;
 if item_count<1 then raise exception 'INSTALLMENTS_REQUIRED'; end if;
 if amount_sum<>p_total_amount then raise exception 'INSTALLMENT_TOTAL_MUST_MATCH_PLAN'; end if;
 if exists(select 1 from jsonb_array_elements(p_installments) x where (x->>'amount')::numeric<=0 or (x->>'due_date') is null or coalesce(x->>'status','') not in ('PENDENTE','AGENDADO')) then raise exception 'INVALID_INSTALLMENT'; end if;
 if (select count(distinct (x->>'number')::int) from jsonb_array_elements(p_installments)x)<>item_count then raise exception 'DUPLICATE_INSTALLMENT_NUMBER'; end if;
 if (select min((x->>'number')::int) from jsonb_array_elements(p_installments)x)<>1 or (select max((x->>'number')::int) from jsonb_array_elements(p_installments)x)<>item_count then raise exception 'INSTALLMENT_NUMBERS_MUST_BE_CONTIGUOUS'; end if;
 insert into public.installment_plans(organization_id,description,total_amount,installment_count,first_due_date,notes,created_by)
 select p_organization_id,trim(p_description),p_total_amount,item_count,min((x->>'due_date')::date),nullif(trim(p_notes),''),auth.uid() from jsonb_array_elements(p_installments)x returning id into plan_id;
 for item in select value from jsonb_array_elements(p_installments) order by (value->>'number')::int loop
   if (item->>'number')::int<>expected_number then raise exception 'INSTALLMENT_NUMBERS_MUST_BE_CONTIGUOUS'; end if;
   entry_id:=public.save_financial_entry(p_organization_id,null,p_entry_direction,item->>'status',p_issue_date,(item->>'due_date')::date,p_document_number,p_document_name,p_description||' — '||lpad(expected_number::text,2,'0')||'/'||lpad(item_count::text,2,'0'),p_counterparty_id,p_chart_account_id,p_crop_season_id,p_payment_method_id,p_planned_bank_account_id,(item->>'amount')::numeric,p_notes,p_allocation_mode,p_farm_id,p_allocation_rule_id);
   update public.financial_entries set installment_plan_id=plan_id,installment_number=expected_number,installment_total=item_count,source_type='PARCELAMENTO' where id=entry_id;
   expected_number:=expected_number+1;
 end loop;
 set constraints all immediate;
 set constraints all deferred;
 return plan_id;
end$$;
revoke all on function public.create_installment_plan(uuid,text,numeric,date,text,uuid,uuid,uuid,uuid,uuid,text,text,text,text,uuid,uuid,jsonb) from public;
grant execute on function public.create_installment_plan(uuid,text,numeric,date,text,uuid,uuid,uuid,uuid,uuid,text,text,text,text,uuid,uuid,jsonb) to authenticated;

create or replace view public.v_financial_entry_balances with(security_invoker=true) as
select e.organization_id,e.id financial_entry_id,e.amount original_amount,coalesce(sum(s.amount) filter(where s.reversed_at is null),0)::numeric(18,2) settled_amount,
 (e.amount-coalesce(sum(s.amount) filter(where s.reversed_at is null),0))::numeric(18,2) open_amount
from public.financial_entries e left join public.settlements s on s.financial_entry_id=e.id and s.organization_id=e.organization_id
where e.deleted_at is null group by e.organization_id,e.id,e.amount;
grant select on public.v_financial_entry_balances to authenticated;
revoke execute on function private.guard_settlement_insert(),private.guard_settlement_update() from public,authenticated;
