-- FINAGRO Web — Security and integrity hardening v0.2.1
-- Corrections found while running the foundation on Supabase local.

-- Internal trigger/helper functions must never inherit EXECUTE from PUBLIC.
-- authenticated keeps access only to the two RLS predicates explicitly used by policies.
revoke execute on all functions in schema private from public, authenticated;
grant execute on function private.is_org_member(uuid) to authenticated;
grant execute on function private.has_permission(uuid, text) to authenticated;

alter default privileges for role postgres in schema private
revoke execute on functions from public;

-- Reversals must go through public.reverse_settlement(), which validates permission,
-- stamps auth.uid() and requires a reason. Direct table UPDATE would allow forged users.
drop policy if exists settlements_reverse_update on public.settlements;

create or replace function private.guard_settlement_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not exists (
        select 1
        from public.financial_entries e
        where e.id = new.financial_entry_id
          and e.organization_id = new.organization_id
          and e.deleted_at is null
    ) then
        raise exception 'ACTIVE_FINANCIAL_ENTRY_REQUIRED_FOR_SETTLEMENT';
    end if;

    if auth.role() <> 'service_role' then
        if auth.uid() is null then
            raise exception 'AUTH_REQUIRED';
        end if;
        if new.created_by is not null and new.created_by <> auth.uid() then
            raise exception 'SETTLEMENT_CREATED_BY_MUST_MATCH_CALLER';
        end if;
        new.created_by := auth.uid();
    end if;

    return new;
end;
$$;

-- Avoid cross-tenant UUID probing: an unauthorized settlement is indistinguishable
-- from a missing settlement to the RPC caller.
create or replace function public.reverse_settlement(
    p_settlement_id uuid,
    p_reason text,
    p_restore_status text default 'PENDENTE'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    s public.settlements%rowtype;
begin
    if p_restore_status not in ('PENDENTE','AGENDADO') then
        raise exception 'RESTORE_STATUS_MUST_BE_PENDING_OR_SCHEDULED';
    end if;

    select * into s
      from public.settlements
     where id = p_settlement_id
       and (
           auth.role() = 'service_role'
           or private.has_permission(organization_id, 'settlements.reverse')
       )
     for update;
    if not found then raise exception 'SETTLEMENT_NOT_FOUND'; end if;

    if s.reversed_at is not null then
        raise exception 'SETTLEMENT_ALREADY_REVERSED';
    end if;

    if p_reason is null or length(trim(p_reason)) = 0 then
        raise exception 'REVERSAL_REASON_REQUIRED';
    end if;

    if auth.role() <> 'service_role' and auth.uid() is null then
        raise exception 'AUTH_REQUIRED';
    end if;

    update public.settlements
       set reversed_at = now(),
           reversed_by = auth.uid(),
           reversal_reason = trim(p_reason)
     where id = p_settlement_id;

    if p_restore_status = 'AGENDADO' then
        update public.financial_entries
           set status = 'AGENDADO', updated_by = auth.uid()
         where id = s.financial_entry_id
           and status = 'PENDENTE';
    end if;
end;
$$;

-- A plan itself has no financial impact. Linked financial_entries are the parcels.
-- The database prevents duplicate/excess parcel numbers and, once all N parcels
-- exist, requires their exact NUMERIC sum to equal installment_plans.total_amount.
create unique index if not exists uq_financial_entries_installment_number
    on public.financial_entries (installment_plan_id, installment_number)
    where installment_plan_id is not null;

create or replace function private.assert_installment_plan_valid(target_plan uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    plan_row public.installment_plans%rowtype;
    entry_count integer;
    amount_total numeric(18,2);
    invalid_metadata_count integer;
begin
    if target_plan is null then
        return;
    end if;

    select * into plan_row
      from public.installment_plans
     where id = target_plan;
    if not found then
        return;
    end if;

    select count(*), coalesce(sum(e.amount), 0),
           count(*) filter (
               where e.installment_total <> plan_row.installment_count
                  or e.installment_number not between 1 and plan_row.installment_count
           )
      into entry_count, amount_total, invalid_metadata_count
      from public.financial_entries e
     where e.installment_plan_id = target_plan
       and e.deleted_at is null;

    if invalid_metadata_count > 0 then
        raise exception 'INSTALLMENT_METADATA_MUST_MATCH_PLAN';
    end if;
    if entry_count > plan_row.installment_count then
        raise exception 'INSTALLMENT_COUNT_EXCEEDS_PLAN';
    end if;
    if entry_count = plan_row.installment_count and amount_total <> plan_row.total_amount then
        raise exception 'INSTALLMENT_TOTAL_MUST_MATCH_PLAN: plan %, installments %, expected %',
            target_plan, amount_total, plan_row.total_amount;
    end if;
end;
$$;

create or replace function private.check_installment_plan_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'installment_plans' then
        perform private.assert_installment_plan_valid(coalesce(new.id, old.id));
    else
        perform private.assert_installment_plan_valid(coalesce(new.installment_plan_id, old.installment_plan_id));
        if tg_op = 'UPDATE' and new.installment_plan_id is distinct from old.installment_plan_id then
            perform private.assert_installment_plan_valid(old.installment_plan_id);
        end if;
    end if;
    if tg_op = 'DELETE' then return old; end if;
    return new;
end;
$$;

drop trigger if exists trg_installment_plans_consistency on public.installment_plans;
create constraint trigger trg_installment_plans_consistency
after insert or update of total_amount, installment_count on public.installment_plans
deferrable initially deferred
for each row execute function private.check_installment_plan_trigger();

drop trigger if exists trg_financial_entries_installment_consistency on public.financial_entries;
create constraint trigger trg_financial_entries_installment_consistency
after insert or update of installment_plan_id, installment_number, installment_total, amount, deleted_at
or delete on public.financial_entries
deferrable initially deferred
for each row execute function private.check_installment_plan_trigger();

-- The original generic audit trigger referenced typed OLD/NEW fields from only
-- some of its tables. PostgreSQL resolves those record fields even on other table
-- shapes, causing valid updates to fail. Use the already-built JSON documents.
create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    oldj jsonb;
    newj jsonb;
    org uuid;
    entity uuid;
    action_name text;
begin
    oldj := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
    newj := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;

    entity := coalesce((newj->>'id')::uuid, (oldj->>'id')::uuid);
    if tg_table_name = 'role_permissions' then
        entity := coalesce((newj->>'role_id')::uuid, (oldj->>'role_id')::uuid);
    end if;
    if tg_table_name = 'organizations' then
        org := entity;
    else
        org := coalesce((newj->>'organization_id')::uuid, (oldj->>'organization_id')::uuid);
    end if;
    action_name := tg_op;

    if tg_table_name = 'financial_entries' and tg_op = 'UPDATE' then
        if oldj->>'status' is distinct from newj->>'status' then
            action_name := 'STATUS_CHANGE';
        elsif oldj->>'deleted_at' is null and newj->>'deleted_at' is not null then
            action_name := 'SOFT_DELETE';
        end if;
    elsif tg_table_name = 'settlements' and tg_op = 'UPDATE'
          and oldj->>'reversed_at' is null and newj->>'reversed_at' is not null then
        action_name := 'SETTLEMENT_REVERSED';
    end if;

    insert into public.audit_logs (
        organization_id, actor_user_id, entity_type, entity_id,
        action, old_data, new_data
    ) values (
        org, auth.uid(), tg_table_name, entity,
        action_name, oldj, newj
    );

    if tg_op = 'DELETE' then return old; end if;
    return new;
end;
$$;

-- Same PostgreSQL record-shape issue in the original allocation constraint
-- trigger: access allocation-only fields only inside the allocation-table branch.
create or replace function private.check_entry_allocation_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target uuid;
begin
    if tg_table_name = 'financial_entries' then
        target := coalesce(new.id, old.id);
    else
        target := coalesce(new.financial_entry_id, old.financial_entry_id);
    end if;

    perform private.assert_entry_allocation_valid(target);

    if tg_table_name = 'entry_allocations' then
        if tg_op = 'UPDATE' then
            if new.financial_entry_id is distinct from old.financial_entry_id then
                perform private.assert_entry_allocation_valid(old.financial_entry_id);
            end if;
        end if;
    end if;

    if tg_op = 'DELETE' then return old; end if;
    return new;
end;
$$;

-- Re-apply the deny after defining the new private functions.
revoke execute on all functions in schema private from public, authenticated;
grant execute on function private.is_org_member(uuid) to authenticated;
grant execute on function private.has_permission(uuid, text) to authenticated;
