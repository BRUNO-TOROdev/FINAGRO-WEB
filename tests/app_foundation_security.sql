begin;

do $$
declare
    user_a constant uuid := '10000000-0000-0000-0000-000000000001';
    user_b constant uuid := '20000000-0000-0000-0000-000000000002';
    user_reader constant uuid := '30000000-0000-0000-0000-000000000003';
    org_a constant uuid := 'a0000000-0000-0000-0000-000000000001';
    org_b constant uuid := 'b0000000-0000-0000-0000-000000000002';
    owner_a uuid;
    admin_a uuid;
    read_a uuid;
    owner_b uuid;
    membership_a uuid;
    role_name_result text;
begin
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
    values
      (user_a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@app.test', crypt('password', gen_salt('bf')), now(), '{"full_name":"Usuário A"}', now(), now()),
      (user_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@app.test', crypt('password', gen_salt('bf')), now(), '{"full_name":"Usuário B"}', now(), now()),
      (user_reader, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reader@app.test', crypt('password', gen_salt('bf')), now(), '{"full_name":"Somente Leitura"}', now(), now());

    insert into public.organizations (id, legal_name) values (org_a, 'Organização A'), (org_b, 'Organização B');
    perform private.seed_default_roles(org_a, user_a);
    perform private.seed_default_roles(org_b, user_b);
    select id into owner_a from public.roles where organization_id = org_a and name = 'Proprietário';
    select id into admin_a from public.roles where organization_id = org_a and name = 'Administrador';
    select id into read_a from public.roles where organization_id = org_a and name = 'Somente leitura';
    select id into owner_b from public.roles where organization_id = org_b and name = 'Proprietário';
    select id into membership_a from public.memberships where organization_id = org_a and user_id = user_a;
    insert into public.memberships (organization_id, user_id, role_id) values (org_a, user_reader, read_a);
    insert into public.crop_seasons (id, organization_id, name, season_type)
    values ('a1000000-0000-0000-0000-000000000001', org_a, 'Safra original', 'PRINCIPAL');

    if (select slug from public.organizations where id = org_a) !~ '^organiza-o-a-[0-9a-f]{8}$' then
      raise exception 'organization slug was not generated deterministically';
    end if;

    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', user_a::text, true);
    set local role authenticated;

    if (select count(*) from public.list_organization_members(org_a)) <> 2 then
      raise exception 'authorized member list failed';
    end if;
    if (select count(*) from public.list_organization_members(org_b)) <> 0 then
      raise exception 'cross-tenant member data leaked';
    end if;

    insert into public.farms (organization_id, name) values (org_a, 'Fazenda autorizada');
    begin
      insert into public.farms (organization_id, name) values (org_b, 'Fazenda cross-tenant');
      raise exception 'cross-tenant farm insert should fail';
    exception when insufficient_privilege then null;
    end;

    begin
      perform public.change_membership_role(org_a, membership_a, admin_a);
      raise exception 'self role change should fail';
    exception when others then
      if sqlerrm not like '%SELF_ROLE_CHANGE_NOT_ALLOWED%' then raise; end if;
    end;

    begin
      perform public.change_membership_role(org_b, membership_a, owner_b);
      raise exception 'cross-tenant role change should fail';
    exception when others then
      if sqlerrm not like '%PERMISSION_DENIED%' then raise; end if;
    end;

    perform set_config('request.jwt.claim.sub', user_reader::text, true);
    begin
      insert into public.farms (organization_id, name) values (org_a, 'Fazenda READ_ONLY');
      raise exception 'READ_ONLY farm insert should fail';
    exception when insufficient_privilege then null;
    end;
    update public.crop_seasons set name = 'Safra adulterada'
     where id = 'a1000000-0000-0000-0000-000000000001';
    if (select name from public.crop_seasons where id = 'a1000000-0000-0000-0000-000000000001') <> 'Safra original' then
      raise exception 'READ_ONLY changed crop season';
    end if;

    reset role;
    select r.name into role_name_result from public.memberships m join public.roles r on r.id = m.role_id where m.id = membership_a;
    if role_name_result <> 'Proprietário' then raise exception 'role changed after denied operation'; end if;
end $$;

rollback;
