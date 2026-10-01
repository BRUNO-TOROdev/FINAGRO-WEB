-- FINAGRO Web — controlled, traceable and reversible historical import staging.

create table public.import_batches (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 source_file_name text not null, source_file_sha256 text not null, source_sheet text not null default 'Base de Dados',
 status text not null default 'ANALISADO' check(status in ('ANALISADO','CONFIRMADO','REVERTIDO')),
 is_dry_run boolean not null default true, period_start date, period_end date,
 total_rows integer not null default 0, valid_rows integer not null default 0, warning_rows integer not null default 0, blocked_rows integer not null default 0,
 created_by uuid not null references auth.users(id), confirmed_by uuid references auth.users(id), confirmed_at timestamptz,
 reverted_by uuid references auth.users(id), reverted_at timestamptz, created_at timestamptz not null default now(),
 unique(organization_id,source_file_sha256,source_sheet,period_start,period_end), unique(id,organization_id)
);
create table public.import_mappings (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 dimension text not null check(dimension in ('FARM','CROP_SEASON','ALLOCATION_RULE','CHART_ACCOUNT','PARTY','BANK_ACCOUNT','PAYMENT_METHOD','STATUS','DIRECTION')),
 source_value text not null, secondary_source_value text not null default '', target_id uuid, target_value text,
 transformation_rule text not null default 'EXPLICIT_MAPPING', created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(organization_id,dimension,source_value,secondary_source_value), unique(id,organization_id)
);
create table public.import_staging_rows (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, import_batch_id uuid not null,
 source_row_number integer not null, source_row_hash text not null, source_data jsonb not null,
 issue_date date, due_date date, source_group text, source_subgroup text, source_farm text, source_season text,
 source_status text, source_direction text, amount numeric(18,2),
 chart_account_id uuid, farm_id uuid, crop_season_id uuid, allocation_rule_id uuid,
 counterparty_id uuid, bank_account_id uuid, payment_method_id uuid,
 normalized_status text, normalized_direction text, resolution_status text not null check(resolution_status in ('VALID','WARNING','BLOCKED','IMPORTED','ROLLED_BACK')),
 issues jsonb not null default '[]', transformations jsonb not null default '[]', financial_entry_id uuid,
 created_at timestamptz not null default now(), unique(import_batch_id,source_row_number), unique(import_batch_id,source_row_hash), unique(id,organization_id),
 foreign key(import_batch_id,organization_id) references public.import_batches(id,organization_id) on delete cascade,
 foreign key(chart_account_id,organization_id) references public.chart_accounts(id,organization_id),
 foreign key(farm_id,organization_id) references public.farms(id,organization_id),
 foreign key(crop_season_id,organization_id) references public.crop_seasons(id,organization_id),
 foreign key(allocation_rule_id,organization_id) references public.allocation_rules(id,organization_id),
 foreign key(counterparty_id,organization_id) references public.parties(id,organization_id),
 foreign key(bank_account_id,organization_id) references public.bank_accounts(id,organization_id),
 foreign key(payment_method_id,organization_id) references public.payment_methods(id,organization_id),
 foreign key(financial_entry_id,organization_id) references public.financial_entries(id,organization_id)
);
create index idx_import_batches_org_created on public.import_batches(organization_id,created_at desc);
create index idx_import_rows_batch_resolution on public.import_staging_rows(import_batch_id,resolution_status,source_row_number);

alter table public.import_batches enable row level security; alter table public.import_mappings enable row level security; alter table public.import_staging_rows enable row level security;
create policy import_batches_read on public.import_batches for select to authenticated using(private.has_permission(organization_id,'imports.execute') or private.has_permission(organization_id,'audit.view'));
create policy import_mappings_read on public.import_mappings for select to authenticated using(private.has_permission(organization_id,'imports.execute'));
create policy import_rows_read on public.import_staging_rows for select to authenticated using(private.has_permission(organization_id,'imports.execute') or private.has_permission(organization_id,'audit.view'));
grant select on public.import_batches,public.import_mappings,public.import_staging_rows to authenticated;

create or replace function public.analyze_finagro_import(p_organization_id uuid,p_file_name text,p_file_sha256 text,p_period_start date,p_period_end date,p_rows jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare b uuid; r jsonb; n int; issues jsonb; transforms jsonb; account_id uuid; farm_target uuid; season_target uuid; rule_target uuid; party_target uuid; bank_target uuid; method_target uuid; normalized_s text; normalized_d text; amount_v numeric; issue_d date; due_d date; resolution text; group_v text; subgroup_v text; farm_v text; season_v text; status_v text; direction_v text;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'imports.execute') then raise exception 'PERMISSION_DENIED'; end if;
 if p_period_start is null or p_period_end is null or p_period_end<p_period_start then raise exception 'CLOSED_IMPORT_PERIOD_REQUIRED'; end if;
 if jsonb_typeof(p_rows)<>'array' then raise exception 'IMPORT_ROWS_ARRAY_REQUIRED'; end if;
 insert into public.import_batches(organization_id,source_file_name,source_file_sha256,period_start,period_end,total_rows,created_by)
 values(p_organization_id,p_file_name,p_file_sha256,p_period_start,p_period_end,jsonb_array_length(p_rows),auth.uid()) returning id into b;
 for r in select value from jsonb_array_elements(p_rows) loop
  n=(r->>'source_row_number')::int; issues='[]'; transforms='[]'; resolution='VALID';
  group_v=nullif(trim(r->>'group'),''); subgroup_v=nullif(trim(r->>'subgroup'),''); farm_v=nullif(trim(r->>'farm'),''); season_v=nullif(trim(r->>'season'),''); status_v=upper(nullif(trim(r->>'status'),'')); direction_v=upper(nullif(trim(r->>'direction'),''));
  begin issue_d=(r->>'issue_date')::date; exception when others then issue_d=null; end;
  begin due_d=(r->>'due_date')::date; exception when others then due_d=null; end;
  begin amount_v=(r->>'amount')::numeric; exception when others then amount_v=null; end;
  if issue_d is null or due_d is null or issue_d<p_period_start or issue_d>p_period_end then issues=issues||jsonb_build_array(jsonb_build_object('code','INVALID_OR_OUTSIDE_ISSUE_DATE','severity','BLOCKED')); end if;
  if amount_v is null or amount_v<=0 then issues=issues||jsonb_build_array(jsonb_build_object('code','INVALID_AMOUNT','severity','BLOCKED')); end if;
  normalized_s=case coalesce((select upper(m.target_value) from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='STATUS' and upper(m.source_value)=status_v),status_v) when 'PENDENTE' then 'PENDENTE' when 'AGENDADO' then 'AGENDADO' else null end;
  if status_v='PAGO' then issues=issues||jsonb_build_array(jsonb_build_object('code','PAID_SETTLEMENT_POLICY_REQUIRED','severity','BLOCKED'));
  elsif normalized_s is null then issues=issues||jsonb_build_array(jsonb_build_object('code','UNRECOGNIZED_STATUS','severity','BLOCKED','source',status_v)); end if;
  normalized_d=case coalesce((select upper(m.target_value) from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='DIRECTION' and upper(m.source_value)=direction_v),direction_v) when 'E' then 'ENTRADA' when 'S' then 'SAIDA' when 'ENTRADA' then 'ENTRADA' when 'SAIDA' then 'SAIDA' end;
  if normalized_d is null then issues=issues||jsonb_build_array(jsonb_build_object('code','UNRECOGNIZED_DIRECTION','severity','BLOCKED','source',direction_v)); else transforms=transforms||jsonb_build_array(jsonb_build_object('field','direction','source',direction_v,'target',normalized_d,'rule','EXPLICIT_CODE')); end if;
  select c.id into account_id from public.chart_accounts c left join public.chart_accounts p on p.id=c.parent_id and p.organization_id=c.organization_id where c.organization_id=p_organization_id and c.is_active and c.source_name=subgroup_v and p.source_name=group_v limit 1;
  if account_id is null then select m.target_id into account_id from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='CHART_ACCOUNT' and m.source_value=coalesce(group_v,'') and m.secondary_source_value=coalesce(subgroup_v,''); end if;
  if account_id is null then issues=issues||jsonb_build_array(jsonb_build_object('code','CHART_ACCOUNT_NOT_FOUND','severity','BLOCKED')); else transforms=transforms||jsonb_build_array(jsonb_build_object('field','chart_account','rule',case when exists(select 1 from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='CHART_ACCOUNT' and m.target_id=account_id) then 'CONFIGURED_MATCH' else 'EXACT_SOURCE_NAME' end,'target_id',account_id)); end if;
  select s.id into season_target from public.crop_seasons s where s.organization_id=p_organization_id and upper(s.name)=upper(season_v) limit 1;
  if season_target is null then select m.target_id into season_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='CROP_SEASON' and upper(m.source_value)=upper(coalesce(season_v,'')); end if;
  if season_v is not null and season_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','CROP_SEASON_NOT_FOUND','severity','BLOCKED')); end if;
  if upper(coalesce(farm_v,''))='GERAL' then
   select m.target_id into rule_target from public.import_mappings m join public.allocation_rules a on a.id=m.target_id and a.organization_id=m.organization_id and a.crop_season_id=season_target and a.is_active where m.organization_id=p_organization_id and m.dimension='ALLOCATION_RULE' and upper(m.source_value)='GERAL' and upper(m.secondary_source_value)=upper(coalesce(season_v,''));
   if rule_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','GENERAL_REQUIRES_ALLOCATION_RULE','severity','BLOCKED')); end if;
  else
   select f.id into farm_target from public.farms f where f.organization_id=p_organization_id and f.is_active and (upper(f.name)=upper(farm_v) or upper(coalesce(f.internal_code,''))=upper(farm_v)) limit 1;
   if farm_target is null then select m.target_id into farm_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='FARM' and upper(m.source_value)=upper(coalesce(farm_v,'')); end if;
   if farm_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','FARM_NOT_FOUND','severity','BLOCKED')); end if;
  end if;
  select m.target_id into party_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='PARTY' and m.source_value=coalesce(r->>'counterparty','');
  if nullif(trim(r->>'counterparty'),'') is not null and party_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','NEW_COUNTERPARTY_REVIEW_REQUIRED','severity','WARNING')); end if;
  select m.target_id into bank_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='BANK_ACCOUNT' and m.source_value=coalesce(r->>'bank','') and m.secondary_source_value=coalesce(r->>'bank_account','');
  if (nullif(trim(r->>'bank'),'') is not null or nullif(trim(r->>'bank_account'),'') is not null) and bank_target is null then issues=issues||jsonb_build_array(jsonb_build_object('code','BANK_ACCOUNT_NOT_FOUND','severity','WARNING')); end if;
  select m.target_id into method_target from public.import_mappings m where m.organization_id=p_organization_id and m.dimension='PAYMENT_METHOD' and m.source_value=coalesce(r->>'payment_method','');
  if exists(select 1 from jsonb_array_elements(issues) x where x->>'severity'='BLOCKED') then resolution='BLOCKED'; elsif jsonb_array_length(issues)>0 then resolution='WARNING'; end if;
  insert into public.import_staging_rows(organization_id,import_batch_id,source_row_number,source_row_hash,source_data,issue_date,due_date,source_group,source_subgroup,source_farm,source_season,source_status,source_direction,amount,chart_account_id,farm_id,crop_season_id,allocation_rule_id,counterparty_id,bank_account_id,payment_method_id,normalized_status,normalized_direction,resolution_status,issues,transformations)
  values(p_organization_id,b,n,pg_catalog.md5(p_file_sha256||':'||n::text),r,issue_d,due_d,group_v,subgroup_v,farm_v,season_v,status_v,direction_v,amount_v,account_id,farm_target,season_target,rule_target,party_target,bank_target,method_target,normalized_s,normalized_d,resolution,issues,transforms);
 end loop;
 update public.import_batches set valid_rows=(select count(*) from public.import_staging_rows where import_batch_id=b and resolution_status='VALID'),warning_rows=(select count(*) from public.import_staging_rows where import_batch_id=b and resolution_status='WARNING'),blocked_rows=(select count(*) from public.import_staging_rows where import_batch_id=b and resolution_status='BLOCKED') where id=b;
 insert into public.audit_logs(organization_id,actor_user_id,entity_type,entity_id,action,new_data) values(p_organization_id,auth.uid(),'IMPORT_BATCH',b,'IMPORT_ANALYZED',jsonb_build_object('dry_run',true,'row_count',jsonb_array_length(p_rows)));
 return b;
end$$;

create or replace function public.confirm_finagro_import(p_organization_id uuid,p_batch_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare r record; entry_id uuid; imported int:=0;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'imports.execute') then raise exception 'PERMISSION_DENIED'; end if;
 if not exists(select 1 from public.import_batches where id=p_batch_id and organization_id=p_organization_id and status='ANALISADO' and blocked_rows=0) then raise exception 'IMPORT_BATCH_NOT_READY'; end if;
 for r in select * from public.import_staging_rows where import_batch_id=p_batch_id and organization_id=p_organization_id and resolution_status in ('VALID','WARNING') order by source_row_number loop
  entry_id=public.save_financial_entry(p_organization_id,null,r.normalized_direction,r.normalized_status,r.issue_date,r.due_date,r.source_data->>'document_number',r.source_data->>'document_name',coalesce(nullif(r.source_data->>'description',''),'Importação FINAGRO'),r.counterparty_id,r.chart_account_id,r.crop_season_id,r.payment_method_id,r.bank_account_id,r.amount,format('Import batch %s, linha %s',p_batch_id,r.source_row_number),case when r.allocation_rule_id is null then 'DIRETA' else 'RATEIO' end,r.farm_id,r.allocation_rule_id);
  update public.financial_entries set source_type='IMPORTACAO' where id=entry_id;
  update public.import_staging_rows set financial_entry_id=entry_id,resolution_status='IMPORTED' where id=r.id; imported=imported+1;
 end loop;
 update public.import_batches set status='CONFIRMADO',is_dry_run=false,confirmed_by=auth.uid(),confirmed_at=now() where id=p_batch_id;
 insert into public.audit_logs(organization_id,actor_user_id,entity_type,entity_id,action,new_data) values(p_organization_id,auth.uid(),'IMPORT_BATCH',p_batch_id,'IMPORT_CONFIRMED',jsonb_build_object('created_entries',imported)); return imported;
end$$;

create or replace function public.rollback_finagro_import(p_organization_id uuid,p_batch_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare affected int;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'imports.execute') then raise exception 'PERMISSION_DENIED'; end if;
 if not exists(select 1 from public.import_batches where id=p_batch_id and organization_id=p_organization_id and status='CONFIRMADO') then raise exception 'CONFIRMED_IMPORT_BATCH_NOT_FOUND'; end if;
 if exists(select 1 from public.import_staging_rows r join public.settlements s on s.financial_entry_id=r.financial_entry_id and s.reversed_at is null where r.import_batch_id=p_batch_id) then raise exception 'IMPORT_ROLLBACK_REQUIRES_SETTLEMENT_REVERSAL'; end if;
 update public.financial_entries e set deleted_at=now(),updated_by=auth.uid() from public.import_staging_rows r where r.import_batch_id=p_batch_id and r.organization_id=p_organization_id and r.financial_entry_id=e.id and e.organization_id=p_organization_id and e.source_type='IMPORTACAO' and e.deleted_at is null; get diagnostics affected=row_count;
 update public.import_staging_rows set resolution_status='ROLLED_BACK' where import_batch_id=p_batch_id and organization_id=p_organization_id and resolution_status='IMPORTED';
 update public.import_batches set status='REVERTIDO',reverted_by=auth.uid(),reverted_at=now() where id=p_batch_id;
 insert into public.audit_logs(organization_id,actor_user_id,entity_type,entity_id,action,new_data) values(p_organization_id,auth.uid(),'IMPORT_BATCH',p_batch_id,'IMPORT_ROLLED_BACK',jsonb_build_object('reverted_entries',affected)); return affected;
end$$;

create or replace function public.save_import_mapping(p_organization_id uuid,p_dimension text,p_source_value text,p_secondary_source_value text,p_target_id uuid,p_target_value text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'imports.execute') then raise exception 'PERMISSION_DENIED'; end if;
 if p_dimension not in ('FARM','CROP_SEASON','ALLOCATION_RULE','CHART_ACCOUNT','PARTY','BANK_ACCOUNT','PAYMENT_METHOD','STATUS','DIRECTION') then raise exception 'INVALID_IMPORT_MAPPING_DIMENSION'; end if;
 if p_dimension='STATUS' and upper(coalesce(p_target_value,'')) not in ('PENDENTE','AGENDADO') then raise exception 'INVALID_IMPORT_STATUS_TARGET'; end if;
 if p_dimension='DIRECTION' and upper(coalesce(p_target_value,'')) not in ('ENTRADA','SAIDA') then raise exception 'INVALID_IMPORT_DIRECTION_TARGET'; end if;
 if p_target_id is not null and (case p_dimension when 'FARM' then not exists(select 1 from public.farms where id=p_target_id and organization_id=p_organization_id) when 'CROP_SEASON' then not exists(select 1 from public.crop_seasons where id=p_target_id and organization_id=p_organization_id) when 'ALLOCATION_RULE' then not exists(select 1 from public.allocation_rules where id=p_target_id and organization_id=p_organization_id) when 'CHART_ACCOUNT' then not exists(select 1 from public.chart_accounts where id=p_target_id and organization_id=p_organization_id) when 'PARTY' then not exists(select 1 from public.parties where id=p_target_id and organization_id=p_organization_id) when 'BANK_ACCOUNT' then not exists(select 1 from public.bank_accounts where id=p_target_id and organization_id=p_organization_id) when 'PAYMENT_METHOD' then not exists(select 1 from public.payment_methods where id=p_target_id and organization_id=p_organization_id) else false end) then raise exception 'IMPORT_MAPPING_TARGET_NOT_FOUND_IN_ORGANIZATION'; end if;
 insert into public.import_mappings(organization_id,dimension,source_value,secondary_source_value,target_id,target_value,created_by)
 values(p_organization_id,p_dimension,trim(p_source_value),coalesce(trim(p_secondary_source_value),''),p_target_id,p_target_value,auth.uid())
 on conflict(organization_id,dimension,source_value,secondary_source_value) do update set target_id=excluded.target_id,target_value=excluded.target_value,created_by=auth.uid(),created_at=now() returning id into result;
 return result;
end$$;

revoke all on function public.analyze_finagro_import(uuid,text,text,date,date,jsonb) from public; grant execute on function public.analyze_finagro_import(uuid,text,text,date,date,jsonb) to authenticated;
revoke all on function public.confirm_finagro_import(uuid,uuid) from public; grant execute on function public.confirm_finagro_import(uuid,uuid) to authenticated;
revoke all on function public.rollback_finagro_import(uuid,uuid) from public; grant execute on function public.rollback_finagro_import(uuid,uuid) to authenticated;
revoke all on function public.save_import_mapping(uuid,text,text,text,uuid,text) from public; grant execute on function public.save_import_mapping(uuid,text,text,text,uuid,text) to authenticated;
