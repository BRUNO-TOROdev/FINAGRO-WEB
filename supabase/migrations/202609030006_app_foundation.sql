-- FINAGRO Web — Application foundation v0.1
-- Additive support for tenant URLs and safe membership administration.

alter table public.organizations add column slug text;

update public.organizations
set slug = coalesce(
    nullif(trim(both '-' from regexp_replace(lower(legal_name), '[^a-z0-9]+', '-', 'g')), ''),
    'organizacao'
) || '-' || left(id::text, 8);

alter table public.organizations alter column slug set not null;
alter table public.organizations add constraint organizations_slug_key unique (slug);
alter table public.organizations add constraint organizations_slug_format
    check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$');

create or replace function private.set_organization_slug()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    base_slug text;
begin
    if new.slug is null or trim(new.slug) = '' then
        base_slug := nullif(
            trim(both '-' from regexp_replace(lower(new.legal_name), '[^a-z0-9]+', '-', 'g')),
            ''
        );
        new.slug := coalesce(base_slug, 'organizacao') || '-' || left(new.id::text, 8);
    end if;
    return new;
end;
$$;

create trigger trg_organizations_slug
before insert on public.organizations
for each row execute function private.set_organization_slug();

create or replace function private.guard_organization_slug()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.slug is distinct from old.slug then
        raise exception 'ORGANIZATION_SLUG_IS_IMMUTABLE';
    end if;
    return new;
end;
$$;

create trigger trg_organizations_slug_immutable
before update of slug on public.organizations
for each row execute function private.guard_organization_slug();

create or replace function public.list_organization_members(p_organization_id uuid)
returns table (
    membership_id uuid,
    user_id uuid,
    email text,
    display_name text,
    role_id uuid,
    role_name text,
    is_active boolean
)
language sql
stable
security definer
set search_path = ''
as $$
    select m.id,
           m.user_id,
           u.email::text,
           coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),
           r.id,
           r.name,
           m.is_active
      from public.memberships m
      join public.roles r
        on r.id = m.role_id and r.organization_id = m.organization_id
      join auth.users u on u.id = m.user_id
     where m.organization_id = p_organization_id
       and private.has_permission(p_organization_id, 'users.manage')
     order by coalesce(u.raw_user_meta_data->>'full_name', u.email);
$$;

revoke all on function public.list_organization_members(uuid) from public;
grant execute on function public.list_organization_members(uuid) to authenticated;

create or replace function public.change_membership_role(
    p_organization_id uuid,
    p_membership_id uuid,
    p_role_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_user uuid := auth.uid();
    caller_role_name text;
    target_user uuid;
    current_target_role_name text;
    target_role_name text;
begin
    if caller_user is null or not private.has_permission(p_organization_id, 'users.manage') then
        raise exception 'PERMISSION_DENIED';
    end if;

    select r.name into caller_role_name
      from public.memberships m
      join public.roles r on r.id = m.role_id and r.organization_id = m.organization_id
     where m.organization_id = p_organization_id
       and m.user_id = caller_user
       and m.is_active = true;

    select m.user_id, cr.name into target_user, current_target_role_name
      from public.memberships m
      join public.roles cr
        on cr.id = m.role_id and cr.organization_id = m.organization_id
     where m.id = p_membership_id
       and m.organization_id = p_organization_id
       and m.is_active = true
     for update;
    if not found then raise exception 'MEMBERSHIP_NOT_FOUND'; end if;

    select r.name into target_role_name
      from public.roles r
     where r.id = p_role_id
       and r.organization_id = p_organization_id;
    if not found then raise exception 'ROLE_NOT_FOUND'; end if;

    if target_user = caller_user then
        raise exception 'SELF_ROLE_CHANGE_NOT_ALLOWED';
    end if;
    if target_role_name = 'Proprietário' and caller_role_name <> 'Proprietário' then
        raise exception 'ONLY_OWNER_CAN_ASSIGN_OWNER';
    end if;
    if current_target_role_name = 'Proprietário' and caller_role_name <> 'Proprietário' then
        raise exception 'ONLY_OWNER_CAN_CHANGE_OWNER';
    end if;

    update public.memberships set role_id = p_role_id where id = p_membership_id;
end;
$$;

revoke all on function public.change_membership_role(uuid, uuid, uuid) from public;
grant execute on function public.change_membership_role(uuid, uuid, uuid) to authenticated;

revoke execute on function private.set_organization_slug() from public, authenticated;
revoke execute on function private.guard_organization_slug() from public, authenticated;
