-- FINAGRO Web — Operational financial entries foundation v0.1
-- Additive only: migrations 001–008 remain immutable.

create index idx_parties_org_active_name on public.parties (organization_id, is_active, name);
create index idx_bank_accounts_org_active_name on public.bank_accounts (organization_id, is_active, bank_name, account_number);
create index idx_entries_org_direction_due on public.financial_entries (organization_id, entry_direction, due_date desc) where deleted_at is null;
create index idx_entries_org_counterparty_due on public.financial_entries (organization_id, counterparty_id, due_date desc) where deleted_at is null;
create index idx_entries_org_bank_due on public.financial_entries (organization_id, planned_bank_account_id, due_date desc) where deleted_at is null;

create or replace function private.guard_operational_entry_references()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if tg_op = 'UPDATE' and new.organization_id is distinct from old.organization_id then
        raise exception 'FINANCIAL_ENTRY_ORGANIZATION_IS_IMMUTABLE';
    end if;
    if new.counterparty_id is not null
       and (tg_op = 'INSERT' or new.counterparty_id is distinct from old.counterparty_id)
       and not exists (select 1 from public.parties p where p.id=new.counterparty_id and p.organization_id=new.organization_id and p.is_active) then
        raise exception 'ACTIVE_COUNTERPARTY_NOT_FOUND_IN_ORGANIZATION';
    end if;
    if new.planned_bank_account_id is not null
       and (tg_op = 'INSERT' or new.planned_bank_account_id is distinct from old.planned_bank_account_id)
       and not exists (select 1 from public.bank_accounts b where b.id=new.planned_bank_account_id and b.organization_id=new.organization_id and b.is_active) then
        raise exception 'ACTIVE_BANK_ACCOUNT_NOT_FOUND_IN_ORGANIZATION';
    end if;
    if new.payment_method_id is not null
       and (tg_op = 'INSERT' or new.payment_method_id is distinct from old.payment_method_id)
       and not exists (select 1 from public.payment_methods p where p.id=new.payment_method_id and p.organization_id=new.organization_id and p.is_active) then
        raise exception 'ACTIVE_PAYMENT_METHOD_NOT_FOUND_IN_ORGANIZATION';
    end if;
    if auth.role() <> 'service_role' then
        if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
        if tg_op = 'INSERT' then
            if new.created_by is not null and new.created_by <> auth.uid() then raise exception 'ENTRY_CREATED_BY_MUST_MATCH_CALLER'; end if;
            new.created_by := auth.uid();
        elsif new.created_by is distinct from old.created_by then
            raise exception 'ENTRY_CREATED_BY_IS_IMMUTABLE';
        end if;
        new.updated_by := auth.uid();
    end if;
    return new;
end;
$$;

create trigger trg_financial_entries_operational_references
before insert or update of organization_id,counterparty_id,planned_bank_account_id,payment_method_id,created_by,updated_by
on public.financial_entries for each row execute function private.guard_operational_entry_references();

create or replace function public.save_financial_entry(
    p_organization_id uuid, p_entry_id uuid, p_entry_direction text, p_status text,
    p_issue_date date, p_due_date date, p_document_number text, p_document_name text,
    p_description text, p_counterparty_id uuid, p_chart_account_id uuid,
    p_crop_season_id uuid, p_payment_method_id uuid, p_planned_bank_account_id uuid,
    p_amount numeric, p_notes text, p_allocation_mode text, p_farm_id uuid,
    p_allocation_rule_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
    target_id uuid;
    old_entry public.financial_entries%rowtype;
    prior_count integer := 0;
    prior_farm uuid;
    prior_rule uuid;
    allocation_changed boolean := true;
begin
    if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
    if p_entry_direction not in ('ENTRADA','SAIDA') then raise exception 'INVALID_ENTRY_DIRECTION'; end if;
    if p_status not in ('PENDENTE','AGENDADO') then raise exception 'MANUAL_ENTRY_STATUS_MUST_BE_PENDING_OR_SCHEDULED'; end if;
    if p_amount is null or p_amount <= 0 then raise exception 'FINANCIAL_ENTRY_AMOUNT_MUST_BE_POSITIVE'; end if;
    if p_issue_date is null or p_due_date is null then raise exception 'ENTRY_DATES_REQUIRED'; end if;
    if p_description is null or length(trim(p_description)) < 2 then raise exception 'ENTRY_DESCRIPTION_REQUIRED'; end if;
    if p_allocation_mode not in ('DIRETA','RATEIO') then raise exception 'INVALID_ALLOCATION_MODE'; end if;

    if p_entry_id is null then
        if not private.has_permission(p_organization_id,'entries.create') then raise exception 'PERMISSION_DENIED'; end if;
    else
        if not private.has_permission(p_organization_id,'entries.update') then raise exception 'PERMISSION_DENIED'; end if;
        select * into old_entry from public.financial_entries
         where id=p_entry_id and organization_id=p_organization_id and deleted_at is null for update;
        if not found then raise exception 'FINANCIAL_ENTRY_NOT_FOUND'; end if;
        if old_entry.status='PAGO' then raise exception 'PAID_ENTRY_IS_READ_ONLY'; end if;
        if exists(select 1 from public.settlements s where s.financial_entry_id=p_entry_id and s.reversed_at is null) then
            raise exception 'ENTRY_WITH_SETTLEMENT_IS_READ_ONLY';
        end if;
        select count(*),
               (array_agg(a.farm_id order by a.farm_id))[1],
               (array_agg(a.allocation_rule_id order by a.allocation_rule_id)
                 filter (where a.allocation_rule_id is not null))[1]
          into prior_count,prior_farm,prior_rule from public.entry_allocations a where a.financial_entry_id=p_entry_id;
        allocation_changed := old_entry.amount is distinct from p_amount
          or (p_allocation_mode='DIRETA' and (prior_count<>1 or prior_rule is not null or prior_farm is distinct from p_farm_id))
          or (p_allocation_mode='RATEIO' and (prior_count=0 or prior_rule is distinct from p_allocation_rule_id));
    end if;

    if not exists(select 1 from public.chart_accounts c where c.id=p_chart_account_id and c.organization_id=p_organization_id
                  and (c.is_active or (p_entry_id is not null and c.id=old_entry.chart_account_id))) then
        raise exception 'ACTIVE_CHART_ACCOUNT_NOT_FOUND_IN_ORGANIZATION';
    end if;
    if p_crop_season_id is not null and not exists(select 1 from public.crop_seasons s where s.id=p_crop_season_id and s.organization_id=p_organization_id) then
        raise exception 'CROP_SEASON_NOT_FOUND_IN_ORGANIZATION';
    end if;
    if p_counterparty_id is not null and not exists(select 1 from public.parties p where p.id=p_counterparty_id and p.organization_id=p_organization_id
                  and (p.is_active or (p_entry_id is not null and p.id=old_entry.counterparty_id))) then
        raise exception 'ACTIVE_COUNTERPARTY_NOT_FOUND_IN_ORGANIZATION';
    end if;
    if p_planned_bank_account_id is not null and not exists(select 1 from public.bank_accounts b where b.id=p_planned_bank_account_id and b.organization_id=p_organization_id
                  and (b.is_active or (p_entry_id is not null and b.id=old_entry.planned_bank_account_id))) then
        raise exception 'ACTIVE_BANK_ACCOUNT_NOT_FOUND_IN_ORGANIZATION';
    end if;
    if p_payment_method_id is not null and not exists(select 1 from public.payment_methods m where m.id=p_payment_method_id and m.organization_id=p_organization_id
                  and (m.is_active or (p_entry_id is not null and m.id=old_entry.payment_method_id))) then
        raise exception 'ACTIVE_PAYMENT_METHOD_NOT_FOUND_IN_ORGANIZATION';
    end if;
    if p_allocation_mode='DIRETA' then
        if p_farm_id is null or p_allocation_rule_id is not null then raise exception 'DIRECT_ALLOCATION_REQUIRES_ONE_FARM'; end if;
        if not exists(select 1 from public.farms f where f.id=p_farm_id and f.organization_id=p_organization_id and f.is_active) then
            raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION';
        end if;
    else
        if p_allocation_rule_id is null or p_farm_id is not null then raise exception 'RULE_ALLOCATION_REQUIRES_ONE_RULE'; end if;
        if not exists(select 1 from public.allocation_rules r where r.id=p_allocation_rule_id and r.organization_id=p_organization_id and r.is_active
                      and r.crop_season_id=p_crop_season_id) then
            raise exception 'ACTIVE_ALLOCATION_RULE_MUST_MATCH_ENTRY_SEASON';
        end if;
    end if;

    if p_entry_id is null then
        insert into public.financial_entries(
            organization_id,entry_direction,status,issue_date,due_date,document_number,document_name,
            description,counterparty_id,chart_account_id,crop_season_id,payment_method_id,
            planned_bank_account_id,amount,source_type,notes,created_by,updated_by
        ) values (
            p_organization_id,p_entry_direction,p_status,p_issue_date,p_due_date,nullif(trim(p_document_number),''),
            nullif(trim(p_document_name),''),trim(p_description),p_counterparty_id,p_chart_account_id,
            p_crop_season_id,p_payment_method_id,p_planned_bank_account_id,p_amount,'MANUAL',nullif(trim(p_notes),''),auth.uid(),auth.uid()
        ) returning id into target_id;
    else
        target_id := p_entry_id;
        update public.financial_entries set
            entry_direction=p_entry_direction,status=p_status,issue_date=p_issue_date,due_date=p_due_date,
            document_number=nullif(trim(p_document_number),''),document_name=nullif(trim(p_document_name),''),
            description=trim(p_description),counterparty_id=p_counterparty_id,chart_account_id=p_chart_account_id,
            crop_season_id=p_crop_season_id,payment_method_id=p_payment_method_id,
            planned_bank_account_id=p_planned_bank_account_id,amount=p_amount,notes=nullif(trim(p_notes),''),updated_by=auth.uid()
        where id=target_id;
    end if;

    if p_entry_id is null or allocation_changed then
        if p_allocation_mode='DIRETA' then
            perform public.apply_direct_farm_allocation(target_id,p_farm_id);
        else
            perform public.apply_allocation_rule(target_id,p_allocation_rule_id);
        end if;
    end if;
    return target_id;
end;
$$;

revoke all on function public.save_financial_entry(uuid,uuid,text,text,date,date,text,text,text,uuid,uuid,uuid,uuid,uuid,numeric,text,text,uuid,uuid) from public;
grant execute on function public.save_financial_entry(uuid,uuid,text,text,date,date,text,text,text,uuid,uuid,uuid,uuid,uuid,numeric,text,text,uuid,uuid) to authenticated;

create or replace function public.list_financial_entries_page(
    p_organization_id uuid, p_page integer default 1, p_page_size integer default 25,
    p_search text default null, p_due_from date default null, p_due_to date default null,
    p_issue_from date default null, p_issue_to date default null, p_status text default null,
    p_direction text default null, p_counterparty_id uuid default null, p_chart_account_id uuid default null,
    p_farm_id uuid default null, p_crop_season_id uuid default null
) returns table(
    id uuid,entry_direction text,status text,issue_date date,due_date date,document_number text,
    description text,amount numeric,counterparty_name text,chart_account_code text,chart_account_name text,
    crop_season_name text,allocation_mode text,allocation_summary text,total_count bigint
) language sql stable security invoker set search_path = '' as $$
    select e.id,e.entry_direction,e.status,e.issue_date,e.due_date,e.document_number,e.description,e.amount,
           p.name,c.code,c.name,s.name,
           case when a.allocation_rule_id is null then 'DIRETA' else 'RATEIO' end,
           case when a.allocation_rule_id is null then a.farm_names else a.snapshot_rule_name end,
           count(*) over()
      from public.financial_entries e
      left join public.parties p on p.id=e.counterparty_id and p.organization_id=e.organization_id
      join public.chart_accounts c on c.id=e.chart_account_id and c.organization_id=e.organization_id
      left join public.crop_seasons s on s.id=e.crop_season_id and s.organization_id=e.organization_id
      join lateral (
          select (array_agg(x.allocation_rule_id order by x.allocation_rule_id)
                    filter (where x.allocation_rule_id is not null))[1] allocation_rule_id,
                 max(x.snapshot_rule_name) snapshot_rule_name,
                 string_agg(f.name,', ' order by f.name) farm_names
            from public.entry_allocations x join public.farms f on f.id=x.farm_id and f.organization_id=x.organization_id
           where x.financial_entry_id=e.id and x.organization_id=e.organization_id
      ) a on true
     where e.organization_id=p_organization_id and e.deleted_at is null
       and (p_search is null or e.description ilike '%'||p_search||'%' or e.document_number ilike '%'||p_search||'%' or p.name ilike '%'||p_search||'%')
       and (p_due_from is null or e.due_date>=p_due_from) and (p_due_to is null or e.due_date<=p_due_to)
       and (p_issue_from is null or e.issue_date>=p_issue_from) and (p_issue_to is null or e.issue_date<=p_issue_to)
       and (p_status is null or e.status=p_status) and (p_direction is null or e.entry_direction=p_direction)
       and (p_counterparty_id is null or e.counterparty_id=p_counterparty_id)
       and (p_chart_account_id is null or e.chart_account_id=p_chart_account_id)
       and (p_crop_season_id is null or e.crop_season_id=p_crop_season_id)
       and (p_farm_id is null or exists(select 1 from public.entry_allocations fa where fa.financial_entry_id=e.id and fa.farm_id=p_farm_id))
     order by e.due_date desc,e.created_at desc,e.id
     limit greatest(1,least(coalesce(p_page_size,25),100))
    offset (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,25),100));
$$;

revoke all on function public.list_financial_entries_page(uuid,integer,integer,text,date,date,date,date,text,text,uuid,uuid,uuid,uuid) from public;
grant execute on function public.list_financial_entries_page(uuid,integer,integer,text,date,date,date,date,text,text,uuid,uuid,uuid,uuid) to authenticated;

revoke execute on function private.guard_operational_entry_references() from public,authenticated;
