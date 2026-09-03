-- FINAGRO Web — Official FINAGRO chart template integration and RLS tests.
begin;

create schema test_finagro_template;
create function test_finagro_template.assert_true(condition boolean, message text)
returns void language plpgsql set search_path = '' as $$
begin
    if condition is not true then raise exception 'TEST FAILED: %', message; end if;
end;
$$;
grant usage on schema test_finagro_template to authenticated;
grant execute on all functions in schema test_finagro_template to authenticated;

select test_finagro_template.assert_true(
    (select count(*) from public.chart_account_templates where id='3269e51b-12de-5887-a85c-4461af91b4e9' and name='FINAGRO' and version='1.0.0' and is_active)=1,
    'official template exists and is active'
);
select test_finagro_template.assert_true(
    (select count(*) from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9')=154,
    'template total is 154'
);
select test_finagro_template.assert_true(
    (select count(*) from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9' and source_type='GRUPO')=27,
    'template has 27 groups'
);
select test_finagro_template.assert_true(
    (select count(*) from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9' and source_type='SUBGRUPO')=127,
    'template has 127 subgroups'
);
select test_finagro_template.assert_true(
    not exists(select 1 from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9' and name like '%\_%' escape '\'),
    'display names contain no underscore'
);
select test_finagro_template.assert_true(
    not exists(select 1 from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9' and (source_name is null or source_origin is null or source_type is null)),
    'source traceability is complete'
);
select test_finagro_template.assert_true(
    not exists(
        select 1 from public.chart_account_template_items child
        left join public.chart_account_template_items parent on parent.id=child.parent_item_id and parent.template_id=child.template_id
        where child.template_id='3269e51b-12de-5887-a85c-4461af91b4e9'
          and child.source_type='SUBGRUPO'
          and (parent.id is null or parent.source_type<>'GRUPO')
    ),
    'every subgroup has the correct structural parent type'
);
select test_finagro_template.assert_true(
    not exists(select 1 from information_schema.columns where table_schema='public' and table_name='chart_account_templates' and column_name='organization_id'),
    'template is not operationally owned by an organization'
);
select test_finagro_template.assert_true(
    (select count(*) from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9' and name='Entrada de Financiamento')=2,
    'authorized financing parent-child display collision is preserved'
);
select test_finagro_template.assert_true(
    (select count(*) from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9' and name='Saldo Inicial de Caixa')=2,
    'authorized opening balance parent-child display collision is preserved'
);

insert into auth.users (id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('74000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','template-a@example.test','unused',now(),'{}','{}',now(),now()),
('75000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','template-b@example.test','unused',now(),'{}','{}',now(),now());
insert into public.organizations (id,legal_name) values
('74000000-0000-0000-0000-000000000010','TEMPLATE A'),
('75000000-0000-0000-0000-000000000020','TEMPLATE B');
select private.seed_default_roles('74000000-0000-0000-0000-000000000010','74000000-0000-0000-0000-000000000001');
select private.seed_default_roles('75000000-0000-0000-0000-000000000020','75000000-0000-0000-0000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','74000000-0000-0000-0000-000000000001',true);
select test_finagro_template.assert_true(
    public.apply_chart_account_template('74000000-0000-0000-0000-000000000010','3269e51b-12de-5887-a85c-4461af91b4e9'),
    'organization A first application succeeds'
);
select test_finagro_template.assert_true(
    not public.apply_chart_account_template('74000000-0000-0000-0000-000000000010','3269e51b-12de-5887-a85c-4461af91b4e9'),
    'organization A repeated application is idempotent'
);
select test_finagro_template.assert_true(
    (select count(*) from public.chart_accounts where organization_id='74000000-0000-0000-0000-000000000010' and source_template_id='3269e51b-12de-5887-a85c-4461af91b4e9')=154,
    'organization A owns exactly 154 copied accounts'
);
select test_finagro_template.assert_true(
    (select count(*) from public.chart_accounts where organization_id='75000000-0000-0000-0000-000000000020')=0,
    'RLS hides organization B from A before application'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','75000000-0000-0000-0000-000000000002',true);
select test_finagro_template.assert_true(
    public.apply_chart_account_template('75000000-0000-0000-0000-000000000020','3269e51b-12de-5887-a85c-4461af91b4e9'),
    'organization B first application succeeds independently'
);
select test_finagro_template.assert_true(
    (select count(*) from public.chart_accounts where organization_id='75000000-0000-0000-0000-000000000020' and source_template_id='3269e51b-12de-5887-a85c-4461af91b4e9')=154,
    'organization B owns exactly 154 copied accounts'
);
select test_finagro_template.assert_true(
    (select count(*) from public.chart_accounts where organization_id='74000000-0000-0000-0000-000000000010')=0,
    'RLS hides organization A from B'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','74000000-0000-0000-0000-000000000001',true);
update public.chart_accounts set name='Nome exclusivo A'
 where organization_id='74000000-0000-0000-0000-000000000010' and code='FINAGRO-V1-G001';
update public.chart_accounts set name='INVASÃO B'
 where organization_id='75000000-0000-0000-0000-000000000020' and code='FINAGRO-V1-G001';

reset role;
select test_finagro_template.assert_true(
    (select name from public.chart_accounts where organization_id='74000000-0000-0000-0000-000000000010' and code='FINAGRO-V1-G001')='Nome exclusivo A',
    'organization A can customize its own copy'
);
select test_finagro_template.assert_true(
    (select name from public.chart_accounts where organization_id='75000000-0000-0000-0000-000000000020' and code='FINAGRO-V1-G001')='Cancelamentos e Devoluções de Vendas',
    'A cannot alter organization B copy'
);
select test_finagro_template.assert_true(
    (select name from public.chart_account_template_items where template_id='3269e51b-12de-5887-a85c-4461af91b4e9' and code='FINAGRO-V1-G001')='Cancelamentos e Devoluções de Vendas',
    'organization customization does not alter template'
);
select test_finagro_template.assert_true(
    (select count(*) from public.organization_chart_template_applications where template_id='3269e51b-12de-5887-a85c-4461af91b4e9')=2,
    'one application record exists per organization'
);

rollback;
