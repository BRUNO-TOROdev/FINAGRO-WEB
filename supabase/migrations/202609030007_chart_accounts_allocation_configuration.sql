-- FINAGRO Web — Chart of accounts and allocation configuration v0.1
-- Additive only: migrations 001–006 remain immutable.

-- =========================================================
-- CHART ACCOUNT HIERARCHY
-- =========================================================

alter table public.chart_accounts
    add column level integer not null default 1,
    add column source_template_id uuid,
    add column source_template_item_id uuid,
    add column source_template_version text,
    add constraint chart_accounts_level_positive check (level > 0),
    add constraint chart_accounts_source_template_fk
        foreign key (source_template_id)
        references public.chart_account_templates(id),
    add constraint chart_accounts_source_template_item_fk
        foreign key (source_template_item_id, source_template_id)
        references public.chart_account_template_items(id, template_id);

create index idx_chart_accounts_org_parent_order
    on public.chart_accounts (organization_id, parent_id, display_order, code);

create or replace function private.set_chart_account_level_and_guard_cycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    parent_level integer;
begin
    if tg_op = 'UPDATE' and new.organization_id is distinct from old.organization_id then
        raise exception 'CHART_ACCOUNT_ORGANIZATION_IS_IMMUTABLE';
    end if;

    if new.parent_id is null then
        new.level := 1;
        return new;
    end if;

    if new.parent_id = new.id then
        raise exception 'CHART_ACCOUNT_CANNOT_PARENT_ITSELF';
    end if;

    if tg_op = 'UPDATE' and exists (
        with recursive descendants as (
            select c.id
              from public.chart_accounts c
             where c.parent_id = new.id
               and c.organization_id = new.organization_id
            union all
            select c.id
              from public.chart_accounts c
              join descendants d on c.parent_id = d.id
             where c.organization_id = new.organization_id
        )
        select 1 from descendants where id = new.parent_id
    ) then
        raise exception 'CHART_ACCOUNT_HIERARCHY_CYCLE';
    end if;

    select c.level into parent_level
      from public.chart_accounts c
     where c.id = new.parent_id
       and c.organization_id = new.organization_id;
    if not found then
        raise exception 'CHART_ACCOUNT_PARENT_NOT_FOUND';
    end if;

    new.level := parent_level + 1;
    return new;
end;
$$;

create trigger trg_chart_accounts_hierarchy_guard
before insert or update of organization_id, parent_id
on public.chart_accounts
for each row execute function private.set_chart_account_level_and_guard_cycle();

create or replace function private.refresh_chart_account_descendant_levels()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.parent_id is distinct from old.parent_id then
        with recursive descendants as (
            select c.id, new.level + 1 as expected_level
              from public.chart_accounts c
             where c.parent_id = new.id
               and c.organization_id = new.organization_id
            union all
            select c.id, d.expected_level + 1
              from public.chart_accounts c
              join descendants d on c.parent_id = d.id
             where c.organization_id = new.organization_id
        )
        update public.chart_accounts c
           set level = d.expected_level
          from descendants d
         where c.id = d.id
           and c.level is distinct from d.expected_level;
    end if;
    return new;
end;
$$;

create trigger trg_chart_accounts_refresh_descendant_levels
after update of parent_id on public.chart_accounts
for each row execute function private.refresh_chart_account_descendant_levels();

-- =========================================================
-- TEMPLATE APPLICATIONS
-- =========================================================

create table public.organization_chart_template_applications (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    template_id uuid not null references public.chart_account_templates(id),
    template_version text not null,
    applied_by uuid not null references auth.users(id),
    applied_at timestamptz not null default now(),
    unique (organization_id, template_id),
    unique (id, organization_id)
);

alter table public.organization_chart_template_applications enable row level security;

create policy chart_template_applications_read
on public.organization_chart_template_applications
for select to authenticated
using (private.has_permission(organization_id, 'chart_accounts.view'));

create or replace function public.apply_chart_account_template(
    p_organization_id uuid,
    p_template_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    template_row public.chart_account_templates%rowtype;
    application_id uuid;
    item record;
    id_map jsonb := '{}'::jsonb;
    new_account_id uuid;
    new_parent_id uuid;
begin
    if auth.uid() is null
       or not private.has_permission(p_organization_id, 'chart_accounts.manage') then
        raise exception 'PERMISSION_DENIED';
    end if;

    select * into template_row
      from public.chart_account_templates
     where id = p_template_id
       and is_active = true;
    if not found then raise exception 'CHART_ACCOUNT_TEMPLATE_NOT_FOUND'; end if;

    if not exists (
        select 1 from public.chart_account_template_items where template_id = p_template_id
    ) then
        raise exception 'CHART_ACCOUNT_TEMPLATE_HAS_NO_ITEMS';
    end if;

    insert into public.organization_chart_template_applications (
        organization_id, template_id, template_version, applied_by
    ) values (
        p_organization_id, p_template_id, template_row.version, auth.uid()
    )
    on conflict (organization_id, template_id) do nothing
    returning id into application_id;

    if application_id is null then
        return false;
    end if;

    for item in
        with recursive template_tree as (
            select i.*, 1 as depth
              from public.chart_account_template_items i
             where i.template_id = p_template_id
               and i.parent_item_id is null
            union all
            select i.*, t.depth + 1
              from public.chart_account_template_items i
              join template_tree t on i.parent_item_id = t.id
             where i.template_id = p_template_id
        )
        select * from template_tree order by depth, display_order, code
    loop
        new_account_id := gen_random_uuid();
        new_parent_id := case
            when item.parent_item_id is null then null
            else (id_map ->> item.parent_item_id::text)::uuid
        end;

        insert into public.chart_accounts (
            id, organization_id, parent_id, code, name,
            managerial_type, nature, participates_dre, participates_cashflow,
            requires_farm, allows_allocation, requires_crop_season,
            display_order, source_template_id, source_template_item_id,
            source_template_version
        ) values (
            new_account_id, p_organization_id, new_parent_id, item.code, item.name,
            item.managerial_type, item.nature, item.participates_dre, item.participates_cashflow,
            item.requires_farm, item.allows_allocation, item.requires_crop_season,
            item.display_order, p_template_id, item.id, template_row.version
        );

        id_map := id_map || jsonb_build_object(item.id::text, new_account_id::text);
    end loop;

    return true;
end;
$$;

revoke all on function public.apply_chart_account_template(uuid, uuid) from public;
grant execute on function public.apply_chart_account_template(uuid, uuid) to authenticated;

-- =========================================================
-- ATOMIC ALLOCATION RULE CONFIGURATION
-- =========================================================

create or replace function public.save_allocation_rule(
    p_organization_id uuid,
    p_rule_id uuid,
    p_name text,
    p_crop_season_id uuid,
    p_description text,
    p_is_active boolean,
    p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_rule_id uuid;
    item_count integer;
    distinct_farms integer;
    percentage_total numeric(12,6);
begin
    if auth.uid() is null
       or not private.has_permission(p_organization_id, 'allocation_rules.manage') then
        raise exception 'PERMISSION_DENIED';
    end if;
    if p_name is null or length(trim(p_name)) < 2 then
        raise exception 'ALLOCATION_RULE_NAME_REQUIRED';
    end if;
    if jsonb_typeof(p_items) <> 'array' then
        raise exception 'ALLOCATION_RULE_ITEMS_REQUIRED';
    end if;
    if not exists (
        select 1 from public.crop_seasons s
         where s.id = p_crop_season_id
           and s.organization_id = p_organization_id
    ) then
        raise exception 'CROP_SEASON_NOT_FOUND_IN_ORGANIZATION';
    end if;

    select count(*), count(distinct x.farm_id), coalesce(sum(x.percentage), 0)
      into item_count, distinct_farms, percentage_total
      from jsonb_to_recordset(p_items) as x(farm_id uuid, percentage numeric(9,6));

    if item_count = 0 then raise exception 'ALLOCATION_RULE_ITEMS_REQUIRED'; end if;
    if item_count <> distinct_farms then raise exception 'ALLOCATION_RULE_DUPLICATE_FARM'; end if;
    if exists (
        select 1 from jsonb_to_recordset(p_items) as x(farm_id uuid, percentage numeric(9,6))
         where x.percentage <= 0 or x.percentage > 100
    ) then
        raise exception 'ALLOCATION_RULE_PERCENTAGE_OUT_OF_RANGE';
    end if;
    if exists (
        select 1 from jsonb_to_recordset(p_items) as x(farm_id uuid, percentage numeric(9,6))
         where not exists (
             select 1 from public.farms f
              where f.id = x.farm_id
                and f.organization_id = p_organization_id
         )
    ) then
        raise exception 'FARM_NOT_FOUND_IN_ORGANIZATION';
    end if;
    if p_is_active and percentage_total <> 100.000000 then
        raise exception 'ALLOCATION_RULE_MUST_TOTAL_100: total %', percentage_total;
    end if;

    if p_rule_id is null then
        insert into public.allocation_rules (
            organization_id, crop_season_id, name, description, is_active
        ) values (
            p_organization_id, p_crop_season_id, trim(p_name), nullif(trim(p_description), ''), false
        ) returning id into target_rule_id;
    else
        select id into target_rule_id
          from public.allocation_rules
         where id = p_rule_id
           and organization_id = p_organization_id
         for update;
        if not found then raise exception 'ALLOCATION_RULE_NOT_FOUND'; end if;

        update public.allocation_rules
           set crop_season_id = p_crop_season_id,
               name = trim(p_name),
               description = nullif(trim(p_description), ''),
               is_active = false
         where id = target_rule_id;
    end if;

    delete from public.allocation_rule_items where allocation_rule_id = target_rule_id;

    insert into public.allocation_rule_items (
        organization_id, allocation_rule_id, farm_id, percentage
    )
    select p_organization_id, target_rule_id, x.farm_id, x.percentage
      from jsonb_to_recordset(p_items) as x(farm_id uuid, percentage numeric(9,6));

    update public.allocation_rules
       set is_active = p_is_active
     where id = target_rule_id;

    return target_rule_id;
end;
$$;

revoke all on function public.save_allocation_rule(uuid, uuid, text, uuid, text, boolean, jsonb) from public;
grant execute on function public.save_allocation_rule(uuid, uuid, text, uuid, text, boolean, jsonb) to authenticated;

create trigger trg_chart_template_applications_audit
after insert or update or delete on public.organization_chart_template_applications
for each row execute function private.audit_row_change();

revoke execute on function private.set_chart_account_level_and_guard_cycle() from public, authenticated;
revoke execute on function private.refresh_chart_account_descendant_levels() from public, authenticated;
