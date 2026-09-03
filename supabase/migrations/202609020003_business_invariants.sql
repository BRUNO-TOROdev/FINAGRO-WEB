-- FINAGRO Web — Business Invariants, Allocation Engine, Settlements and Audit v0.2

-- =========================================================
-- UPDATED_AT
-- =========================================================

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

-- Tables that expose updated_at.
do $$
declare
    t text;
begin
    foreach t in array array[
        'organizations','roles','role_permissions','memberships','farms','crop_seasons','chart_accounts',
        'parties','bank_accounts','payment_methods','allocation_rules','allocation_rule_items',
        'installment_plans','financial_entries','entry_allocations','settlements',
        'financing_contracts','financing_installments','budgets','budget_items','budget_item_allocations'
    ]
    loop
        execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
        execute format(
            'create trigger trg_%I_updated_at before update on public.%I for each row execute function private.set_updated_at()',
            t, t
        );
    end loop;
end $$;

-- =========================================================
-- ALLOCATION RULE VALIDITY
-- Active rules must sum exactly 100.000000%.
-- Inactive rules may be edited as drafts.
-- =========================================================

create or replace function private.assert_allocation_rule_valid(target_rule uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    active boolean;
    total numeric(12,6);
    item_count integer;
begin
    select r.is_active
      into active
      from public.allocation_rules r
     where r.id = target_rule;

    if not found or active is false then
        return;
    end if;

    select coalesce(sum(i.percentage), 0), count(*)
      into total, item_count
      from public.allocation_rule_items i
     where i.allocation_rule_id = target_rule;

    if item_count = 0 or total <> 100.000000 then
        raise exception 'ALLOCATION_RULE_MUST_TOTAL_100: rule %, total %', target_rule, total;
    end if;
end;
$$;

create or replace function private.check_allocation_rule_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'allocation_rules' then
        perform private.assert_allocation_rule_valid(coalesce(new.id, old.id));
    else
        perform private.assert_allocation_rule_valid(coalesce(new.allocation_rule_id, old.allocation_rule_id));
        if tg_op = 'UPDATE' and new.allocation_rule_id is distinct from old.allocation_rule_id then
            perform private.assert_allocation_rule_valid(old.allocation_rule_id);
        end if;
    end if;
    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_allocation_rules_total_100 on public.allocation_rules;
create constraint trigger trg_allocation_rules_total_100
after insert or update on public.allocation_rules
deferrable initially deferred
for each row execute function private.check_allocation_rule_trigger();

drop trigger if exists trg_allocation_rule_items_total_100 on public.allocation_rule_items;
create constraint trigger trg_allocation_rule_items_total_100
after insert or update or delete on public.allocation_rule_items
deferrable initially deferred
for each row execute function private.check_allocation_rule_trigger();

-- Prevent changing the safra identity of a rule after it has been applied.
create or replace function private.guard_allocation_rule_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.crop_season_id is distinct from old.crop_season_id
       and exists (
           select 1 from public.entry_allocations a
           where a.allocation_rule_id = old.id
       ) then
        raise exception 'USED_ALLOCATION_RULE_CROP_SEASON_IS_IMMUTABLE';
    end if;
    return new;
end;
$$;

drop trigger if exists trg_allocation_rule_identity_guard on public.allocation_rules;
create trigger trg_allocation_rule_identity_guard
before update of crop_season_id on public.allocation_rules
for each row execute function private.guard_allocation_rule_identity();

-- =========================================================
-- ENTRY ALLOCATION VALIDITY
-- Every active financial entry must be fully appropriated.
-- Snapshot amount must sum exactly to the financial amount.
-- =========================================================

create or replace function private.assert_entry_allocation_valid(target_entry uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    e public.financial_entries%rowtype;
    total_pct numeric(12,6);
    total_amount numeric(18,2);
    allocation_count integer;
    nonnull_rule_count integer;
    distinct_rule_count integer;
    account_allows_allocation boolean;
    rule_season uuid;
    snapshot_missing integer;
begin
    select * into e
      from public.financial_entries
     where id = target_entry;

    if not found or e.deleted_at is not null then
        return;
    end if;

    select
        coalesce(sum(a.percentage), 0),
        coalesce(sum(a.allocated_amount), 0),
        count(*),
        count(a.allocation_rule_id),
        count(distinct a.allocation_rule_id),
        count(*) filter (
            where a.allocation_rule_id is not null
              and (a.snapshot_rule_name is null or a.snapshot_crop_season_name is null)
        )
      into total_pct, total_amount, allocation_count, nonnull_rule_count, distinct_rule_count, snapshot_missing
      from public.entry_allocations a
     where a.financial_entry_id = target_entry;

    if allocation_count = 0 then
        raise exception 'ENTRY_REQUIRES_ALLOCATION: entry %', target_entry;
    end if;

    if total_pct <> 100.000000 then
        raise exception 'ENTRY_ALLOCATION_PERCENT_MUST_TOTAL_100: entry %, total %', target_entry, total_pct;
    end if;

    if total_amount <> e.amount then
        raise exception 'ENTRY_ALLOCATION_AMOUNT_MUST_MATCH_ENTRY: entry %, allocated %, entry amount %',
            target_entry, total_amount, e.amount;
    end if;

    -- A snapshot must be either fully direct or fully derived from one rule.
    if allocation_count > 1 and nonnull_rule_count = 0 then
        raise exception 'MULTI_FARM_ALLOCATION_REQUIRES_RULE: entry %', target_entry;
    end if;

    if nonnull_rule_count > 0 then
        if nonnull_rule_count <> allocation_count or distinct_rule_count <> 1 then
            raise exception 'ENTRY_ALLOCATION_CANNOT_MIX_DIRECT_AND_RULE: entry %', target_entry;
        end if;
        if snapshot_missing > 0 then
            raise exception 'ENTRY_RULE_SNAPSHOT_REQUIRED: entry %', target_entry;
        end if;

        select r.crop_season_id
          into rule_season
          from public.allocation_rules r
          join public.entry_allocations a on a.allocation_rule_id = r.id
         where a.financial_entry_id = target_entry
         limit 1;

        if e.crop_season_id is null or rule_season is distinct from e.crop_season_id then
            raise exception 'ALLOCATION_RULE_SEASON_MUST_MATCH_ENTRY_SEASON: entry %', target_entry;
        end if;
    end if;

    select c.allows_allocation
      into account_allows_allocation
      from public.chart_accounts c
     where c.id = e.chart_account_id;

    if account_allows_allocation is false and allocation_count <> 1 then
        raise exception 'CHART_ACCOUNT_DOES_NOT_ALLOW_MULTI_FARM_ALLOCATION: entry %', target_entry;
    end if;
end;
$$;

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

    if tg_table_name = 'entry_allocations'
       and tg_op = 'UPDATE'
       and new.financial_entry_id is distinct from old.financial_entry_id then
        perform private.assert_entry_allocation_valid(old.financial_entry_id);
    end if;

    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_financial_entries_allocation_balance on public.financial_entries;
create constraint trigger trg_financial_entries_allocation_balance
after insert or update on public.financial_entries
deferrable initially deferred
for each row execute function private.check_entry_allocation_trigger();

drop trigger if exists trg_entry_allocations_balance on public.entry_allocations;
create constraint trigger trg_entry_allocations_balance
after insert or update or delete on public.entry_allocations
deferrable initially deferred
for each row execute function private.check_entry_allocation_trigger();

-- =========================================================
-- CHART ACCOUNT REQUIREMENTS
-- =========================================================

create or replace function private.validate_financial_entry_account_requirements()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    acc public.chart_accounts%rowtype;
begin
    select * into acc
      from public.chart_accounts
     where id = new.chart_account_id
       and organization_id = new.organization_id;

    if not found then
        raise exception 'INVALID_CHART_ACCOUNT';
    end if;

    if acc.is_active is false and (tg_op = 'INSERT' or new.chart_account_id is distinct from old.chart_account_id) then
        raise exception 'INACTIVE_CHART_ACCOUNT';
    end if;

    if acc.requires_crop_season and new.crop_season_id is null then
        raise exception 'CHART_ACCOUNT_REQUIRES_CROP_SEASON';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_financial_entry_account_requirements on public.financial_entries;
create trigger trg_financial_entry_account_requirements
before insert or update of chart_account_id, crop_season_id
on public.financial_entries
for each row execute function private.validate_financial_entry_account_requirements();

-- =========================================================
-- FINANCIAL ENTRY MUTATION GUARDS
-- =========================================================

create or replace function private.guard_financial_entry_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    settled_total numeric(18,2);
begin
    if tg_op = 'UPDATE' then
        -- Soft-delete requires explicit permission. Paid entries also require paid-entry permission.
        if old.deleted_at is null and new.deleted_at is not null then
            if auth.role() <> 'service_role' and not private.has_permission(old.organization_id, 'entries.delete') then
                raise exception 'ENTRY_DELETE_PERMISSION_REQUIRED';
            end if;
            if old.status = 'PAGO'
               and auth.role() <> 'service_role'
               and not private.has_permission(old.organization_id, 'entries.manage_paid') then
                raise exception 'PAID_ENTRY_PERMISSION_REQUIRED';
            end if;
        end if;
    end if;

    select coalesce(sum(s.amount), 0)
      into settled_total
      from public.settlements s
     where s.financial_entry_id = new.id
       and s.reversed_at is null;

    if new.status = 'PAGO' and settled_total <> new.amount then
        raise exception 'PAID_ENTRY_REQUIRES_FULL_SETTLEMENT: entry %, settled %, amount %', new.id, settled_total, new.amount;
    end if;

    if new.status <> 'PAGO' and settled_total = new.amount and new.amount > 0 then
        raise exception 'FULLY_SETTLED_ENTRY_MUST_BE_PAID: entry %', new.id;
    end if;

    if settled_total > new.amount then
        raise exception 'SETTLEMENTS_CANNOT_EXCEED_ENTRY_AMOUNT: entry %, settled %, amount %', new.id, settled_total, new.amount;
    end if;

    return new;
end;
$$;

drop trigger if exists trg_financial_entry_mutation_guard on public.financial_entries;
create trigger trg_financial_entry_mutation_guard
before insert or update of status, amount, deleted_at
on public.financial_entries
for each row execute function private.guard_financial_entry_mutation();

-- =========================================================
-- SETTLEMENTS
-- Settlements are immutable. Corrections are reversal + new settlement.
-- Full settlement automatically sets PAGO.
-- Reversal of a full settlement returns the entry to PENDENTE; user may re-schedule it.
-- =========================================================

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
    return new;
end;
$$;

drop trigger if exists trg_settlement_insert_guard on public.settlements;
create trigger trg_settlement_insert_guard
before insert on public.settlements
for each row execute function private.guard_settlement_insert();

create or replace function private.guard_settlement_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if old.reversed_at is not null then
        raise exception 'REVERSED_SETTLEMENT_IS_IMMUTABLE';
    end if;

    if new.organization_id is distinct from old.organization_id
       or new.financial_entry_id is distinct from old.financial_entry_id
       or new.bank_account_id is distinct from old.bank_account_id
       or new.settled_at is distinct from old.settled_at
       or new.amount is distinct from old.amount
       or new.reference is distinct from old.reference
       or new.notes is distinct from old.notes
       or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at then
        raise exception 'SETTLEMENT_CORRECTION_REQUIRES_REVERSAL';
    end if;

    if new.reversed_at is null then
        raise exception 'SETTLEMENT_UPDATE_ONLY_ALLOWED_FOR_REVERSAL';
    end if;

    if new.reversed_by is null or new.reversal_reason is null or length(trim(new.reversal_reason)) = 0 then
        raise exception 'SETTLEMENT_REVERSAL_REQUIRES_USER_AND_REASON';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_settlement_update_guard on public.settlements;
create trigger trg_settlement_update_guard
before update on public.settlements
for each row execute function private.guard_settlement_update();

create or replace function private.sync_entry_from_settlements(target_entry uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    entry_amount numeric(18,2);
    current_status text;
    total numeric(18,2);
begin
    select e.amount, e.status
      into entry_amount, current_status
      from public.financial_entries e
     where e.id = target_entry
       and e.deleted_at is null
     for update;

    if not found then
        return;
    end if;

    select coalesce(sum(s.amount), 0)
      into total
      from public.settlements s
     where s.financial_entry_id = target_entry
       and s.reversed_at is null;

    if total > entry_amount then
        raise exception 'SETTLEMENTS_CANNOT_EXCEED_ENTRY_AMOUNT: entry %, settled %, amount %', target_entry, total, entry_amount;
    elsif total = entry_amount then
        if current_status <> 'PAGO' then
            update public.financial_entries
               set status = 'PAGO', updated_by = coalesce(auth.uid(), updated_by)
             where id = target_entry;
        end if;
    elsif current_status = 'PAGO' then
        update public.financial_entries
           set status = 'PENDENTE', updated_by = coalesce(auth.uid(), updated_by)
         where id = target_entry;
    end if;
end;
$$;

create or replace function private.settlement_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform private.sync_entry_from_settlements(coalesce(new.financial_entry_id, old.financial_entry_id));
    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_settlement_sync_entry on public.settlements;
create trigger trg_settlement_sync_entry
after insert or update on public.settlements
for each row execute function private.settlement_sync_trigger();

-- =========================================================
-- ALLOCATION ENGINE RPCs
-- =========================================================

create or replace function public.apply_direct_farm_allocation(
    p_financial_entry_id uuid,
    p_farm_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    e public.financial_entries%rowtype;
begin
    select * into e
      from public.financial_entries
     where id = p_financial_entry_id
       and deleted_at is null
     for update;

    if not found then raise exception 'ENTRY_NOT_FOUND'; end if;

    if auth.role() <> 'service_role'
       and not (
           private.has_permission(e.organization_id, 'entries.create')
           or private.has_permission(e.organization_id, 'entries.update')
           or private.has_permission(e.organization_id, 'entries.manage_paid')
       ) then
        raise exception 'PERMISSION_DENIED';
    end if;

    if not exists (
        select 1 from public.farms f
        where f.id = p_farm_id
          and f.organization_id = e.organization_id
          and f.is_active = true
    ) then
        raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION';
    end if;

    delete from public.entry_allocations
     where financial_entry_id = e.id;

    insert into public.entry_allocations (
        organization_id, financial_entry_id, farm_id,
        allocation_rule_id, percentage, allocated_amount
    ) values (
        e.organization_id, e.id, p_farm_id,
        null, 100.000000, e.amount
    );
end;
$$;

revoke all on function public.apply_direct_farm_allocation(uuid, uuid) from public;
grant execute on function public.apply_direct_farm_allocation(uuid, uuid) to authenticated;

create or replace function public.apply_allocation_rule(
    p_financial_entry_id uuid,
    p_allocation_rule_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    e public.financial_entries%rowtype;
    r public.allocation_rules%rowtype;
    season_name text;
begin
    select * into e
      from public.financial_entries
     where id = p_financial_entry_id
       and deleted_at is null
     for update;
    if not found then raise exception 'ENTRY_NOT_FOUND'; end if;

    if auth.role() <> 'service_role'
       and not (
           private.has_permission(e.organization_id, 'entries.create')
           or private.has_permission(e.organization_id, 'entries.update')
           or private.has_permission(e.organization_id, 'entries.manage_paid')
       ) then
        raise exception 'PERMISSION_DENIED';
    end if;

    select * into r
      from public.allocation_rules
     where id = p_allocation_rule_id
       and organization_id = e.organization_id;
    if not found then raise exception 'ALLOCATION_RULE_NOT_FOUND'; end if;
    if r.is_active is false then raise exception 'ALLOCATION_RULE_IS_NOT_ACTIVE'; end if;
    if e.crop_season_id is null or e.crop_season_id <> r.crop_season_id then
        raise exception 'ALLOCATION_RULE_SEASON_MUST_MATCH_ENTRY_SEASON';
    end if;

    perform private.assert_allocation_rule_valid(r.id);

    select cs.name into season_name
      from public.crop_seasons cs
     where cs.id = r.crop_season_id;

    delete from public.entry_allocations
     where financial_entry_id = e.id;

    with base as (
        select
            i.farm_id,
            i.percentage,
            round(e.amount * i.percentage / 100.0, 2) as rounded_amount,
            row_number() over (order by i.farm_id) as rn,
            count(*) over () as cnt
        from public.allocation_rule_items i
        where i.allocation_rule_id = r.id
    ), calc as (
        select
            b.*,
            coalesce(sum(b.rounded_amount) over (
                order by b.rn
                rows between unbounded preceding and 1 preceding
            ), 0)::numeric(18,2) as prior_rounded
        from base b
    )
    insert into public.entry_allocations (
        organization_id, financial_entry_id, farm_id, allocation_rule_id,
        percentage, allocated_amount, snapshot_rule_name, snapshot_crop_season_name
    )
    select
        e.organization_id,
        e.id,
        c.farm_id,
        r.id,
        c.percentage,
        case when c.rn = c.cnt
             then e.amount - c.prior_rounded
             else c.rounded_amount
        end,
        r.name,
        season_name
    from calc c
    order by c.rn;
end;
$$;

revoke all on function public.apply_allocation_rule(uuid, uuid) from public;
grant execute on function public.apply_allocation_rule(uuid, uuid) to authenticated;

-- Explicit settlement reversal RPC.
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
     for update;
    if not found then raise exception 'SETTLEMENT_NOT_FOUND'; end if;

    if auth.role() <> 'service_role'
       and not private.has_permission(s.organization_id, 'settlements.reverse') then
        raise exception 'PERMISSION_DENIED';
    end if;

    if s.reversed_at is not null then
        raise exception 'SETTLEMENT_ALREADY_REVERSED';
    end if;

    if p_reason is null or length(trim(p_reason)) = 0 then
        raise exception 'REVERSAL_REASON_REQUIRED';
    end if;

    update public.settlements
       set reversed_at = now(),
           reversed_by = auth.uid(),
           reversal_reason = trim(p_reason)
     where id = p_settlement_id;

    -- settlement trigger first returns a formerly fully-paid entry to PENDENTE.
    if p_restore_status = 'AGENDADO' then
        update public.financial_entries
           set status = 'AGENDADO', updated_by = auth.uid()
         where id = s.financial_entry_id
           and status = 'PENDENTE';
    end if;
end;
$$;

revoke all on function public.reverse_settlement(uuid, text, text) from public;
grant execute on function public.reverse_settlement(uuid, text, text) to authenticated;

-- =========================================================
-- AUDIT LOG
-- =========================================================

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
        if old.status is distinct from new.status then
            action_name := 'STATUS_CHANGE';
        elsif old.deleted_at is null and new.deleted_at is not null then
            action_name := 'SOFT_DELETE';
        end if;
    elsif tg_table_name = 'settlements' and tg_op = 'UPDATE'
          and old.reversed_at is null and new.reversed_at is not null then
        action_name := 'SETTLEMENT_REVERSED';
    end if;

    insert into public.audit_logs (
        organization_id, actor_user_id, entity_type, entity_id,
        action, old_data, new_data
    ) values (
        org, auth.uid(), tg_table_name, entity,
        action_name, oldj, newj
    );

    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

do $$
declare
    t text;
begin
    foreach t in array array[
        'organizations','roles','role_permissions','memberships','farms','crop_seasons','chart_accounts',
        'parties','bank_accounts','payment_methods','allocation_rules','allocation_rule_items',
        'installment_plans','financial_entries','entry_allocations','settlements',
        'financing_contracts','financing_installments','budgets','budget_items','budget_item_allocations'
    ]
    loop
        execute format('drop trigger if exists trg_%I_audit on public.%I', t, t);
        execute format(
            'create trigger trg_%I_audit after insert or update or delete on public.%I for each row execute function private.audit_row_change()',
            t, t
        );
    end loop;
end $$;
