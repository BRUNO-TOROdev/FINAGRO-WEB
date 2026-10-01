-- Historical paid settlements: due date is a disclosed migration surrogate, never bank confirmation.

alter table public.settlements add column date_basis text not null default 'CONFIRMED'
  check(date_basis in ('CONFIRMED','DUE_DATE_SURROGATE'));
alter table public.settlements add column import_batch_id uuid;
alter table public.settlements add column import_staging_row_id uuid;
alter table public.settlements add constraint settlements_import_batch_org_fkey foreign key(import_batch_id,organization_id) references public.import_batches(id,organization_id);
alter table public.settlements add constraint settlements_import_row_org_fkey foreign key(import_staging_row_id,organization_id) references public.import_staging_rows(id,organization_id);
alter table public.settlements add constraint settlements_import_provenance_check check(
 (date_basis='CONFIRMED' and import_batch_id is null and import_staging_row_id is null)
 or (date_basis='DUE_DATE_SURROGATE' and import_batch_id is not null and import_staging_row_id is not null)
);
alter table public.import_staging_rows add column historical_settlement_id uuid;
alter table public.import_staging_rows add constraint import_rows_settlement_org_fkey foreign key(historical_settlement_id,organization_id) references public.settlements(id,organization_id);
create unique index uq_settlement_import_row on public.settlements(import_staging_row_id) where import_staging_row_id is not null;

create or replace function private.guard_settlement_update() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.reversed_at is not null then raise exception 'REVERSED_SETTLEMENT_IS_IMMUTABLE'; end if;
  if new.organization_id is distinct from old.organization_id or new.financial_entry_id is distinct from old.financial_entry_id
    or new.bank_account_id is distinct from old.bank_account_id or new.payment_method_id is distinct from old.payment_method_id
    or new.settled_at is distinct from old.settled_at or new.amount is distinct from old.amount
    or new.reference is distinct from old.reference or new.notes is distinct from old.notes
    or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at
    or new.date_basis is distinct from old.date_basis or new.import_batch_id is distinct from old.import_batch_id
    or new.import_staging_row_id is distinct from old.import_staging_row_id
  then raise exception 'SETTLEMENT_CORRECTION_REQUIRES_REVERSAL'; end if;
  if new.reversed_at is null then raise exception 'SETTLEMENT_UPDATE_ONLY_ALLOWED_FOR_REVERSAL'; end if;
  if new.reversed_by is null or new.reversal_reason is null or length(trim(new.reversal_reason))=0 then raise exception 'SETTLEMENT_REVERSAL_REQUIRES_USER_AND_REASON'; end if;
  return new;
end$$;

-- Preserve the previously homologated analyzer as an internal first pass.
alter function public.analyze_finagro_import(uuid,text,text,date,date,jsonb) rename to analyze_finagro_import_v1;
revoke all on function public.analyze_finagro_import_v1(uuid,text,text,date,date,jsonb) from public,authenticated;
create or replace function public.analyze_finagro_import(p_organization_id uuid,p_file_name text,p_file_sha256 text,p_period_start date,p_period_end date,p_rows jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare b uuid;
begin
 b:=public.analyze_finagro_import_v1(p_organization_id,p_file_name,p_file_sha256,p_period_start,p_period_end,p_rows);
 update public.import_staging_rows r set
  normalized_status='PENDENTE',
  issues=(select coalesce(jsonb_agg(x),'[]'::jsonb) from jsonb_array_elements(r.issues)x where x->>'code'<>'PAID_SETTLEMENT_POLICY_REQUIRED')
    ||case when r.due_date is null then jsonb_build_array(jsonb_build_object('code','HISTORICAL_SETTLEMENT_REFERENCE_DATE_REQUIRED','severity','BLOCKED')) else '[]'::jsonb end
    ||case when r.bank_account_id is null then jsonb_build_array(jsonb_build_object('code','HISTORICAL_PAID_BANK_ACCOUNT_REQUIRED','severity','BLOCKED')) else '[]'::jsonb end,
  transformations=r.transformations||jsonb_build_array(jsonb_build_object('field','settlement_date','source','due_date','target',r.due_date,'rule','DUE_DATE_SURROGATE_NOT_BANK_CONFIRMED'))
 where r.import_batch_id=b and r.source_status='PAGO';
 update public.import_staging_rows r set resolution_status=case
  when exists(select 1 from jsonb_array_elements(r.issues)x where x->>'severity'='BLOCKED') then 'BLOCKED'
  when jsonb_array_length(r.issues)>0 then 'WARNING' else 'VALID' end where r.import_batch_id=b;
 update public.import_batches set valid_rows=(select count(*) from public.import_staging_rows where import_batch_id=b and resolution_status='VALID'),warning_rows=(select count(*) from public.import_staging_rows where import_batch_id=b and resolution_status='WARNING'),blocked_rows=(select count(*) from public.import_staging_rows where import_batch_id=b and resolution_status='BLOCKED') where id=b;
 return b;
end$$;
revoke all on function public.analyze_finagro_import(uuid,text,text,date,date,jsonb) from public;grant execute on function public.analyze_finagro_import(uuid,text,text,date,date,jsonb) to authenticated;

alter function public.confirm_finagro_import(uuid,uuid) rename to confirm_finagro_import_v1;
revoke all on function public.confirm_finagro_import_v1(uuid,uuid) from public,authenticated;
create or replace function public.confirm_finagro_import(p_organization_id uuid,p_batch_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare r record;entry_id uuid;settlement_id uuid;imported int:=0;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'imports.execute') then raise exception 'PERMISSION_DENIED';end if;
 if not exists(select 1 from public.import_batches where id=p_batch_id and organization_id=p_organization_id and status='ANALISADO' and blocked_rows=0) then raise exception 'IMPORT_BATCH_NOT_READY';end if;
 for r in select * from public.import_staging_rows where import_batch_id=p_batch_id and organization_id=p_organization_id and resolution_status in('VALID','WARNING') order by source_row_number loop
  entry_id=public.save_financial_entry(p_organization_id,null,r.normalized_direction,r.normalized_status,r.issue_date,r.due_date,r.source_data->>'document_number',r.source_data->>'document_name',coalesce(nullif(r.source_data->>'description',''),'Importação FINAGRO'),r.counterparty_id,r.chart_account_id,r.crop_season_id,r.payment_method_id,r.bank_account_id,r.amount,format('Import batch %s, linha %s',p_batch_id,r.source_row_number),case when r.allocation_rule_id is null then 'DIRETA' else 'RATEIO' end,r.farm_id,r.allocation_rule_id);
  update public.financial_entries set source_type='IMPORTACAO' where id=entry_id;
  if r.source_status='PAGO' then
   if r.due_date is null or r.bank_account_id is null then raise exception 'HISTORICAL_PAID_ROW_NOT_READY';end if;
   insert into public.settlements(organization_id,financial_entry_id,bank_account_id,payment_method_id,settled_at,amount,reference,notes,created_by,date_basis,import_batch_id,import_staging_row_id)
   values(p_organization_id,entry_id,r.bank_account_id,r.payment_method_id,r.due_date::timestamptz,r.amount,'Migração histórica FINAGRO','Data de vencimento usada como substituta técnica; não confirma a data bancária.',auth.uid(),'DUE_DATE_SURROGATE',p_batch_id,r.id) returning id into settlement_id;
  end if;
  update public.import_staging_rows set financial_entry_id=entry_id,historical_settlement_id=settlement_id,resolution_status='IMPORTED' where id=r.id;settlement_id=null;imported=imported+1;
 end loop;
 update public.import_batches set status='CONFIRMADO',is_dry_run=false,confirmed_by=auth.uid(),confirmed_at=now() where id=p_batch_id;
 insert into public.audit_logs(organization_id,actor_user_id,entity_type,entity_id,action,new_data) values(p_organization_id,auth.uid(),'IMPORT_BATCH',p_batch_id,'IMPORT_CONFIRMED',jsonb_build_object('created_entries',imported,'historical_paid_date_basis','DUE_DATE_SURROGATE'));
 return imported;
end$$;
revoke all on function public.confirm_finagro_import(uuid,uuid) from public;grant execute on function public.confirm_finagro_import(uuid,uuid) to authenticated;

alter function public.rollback_finagro_import(uuid,uuid) rename to rollback_finagro_import_v1;
revoke all on function public.rollback_finagro_import_v1(uuid,uuid) from public,authenticated;
create or replace function public.rollback_finagro_import(p_organization_id uuid,p_batch_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare affected int;
begin
 if auth.uid() is null or not private.has_permission(p_organization_id,'imports.execute') then raise exception 'PERMISSION_DENIED';end if;
 if not exists(select 1 from public.import_batches where id=p_batch_id and organization_id=p_organization_id and status='CONFIRMADO') then raise exception 'CONFIRMED_IMPORT_BATCH_NOT_FOUND';end if;
 if exists(select 1 from public.import_staging_rows r join public.settlements s on s.financial_entry_id=r.financial_entry_id and s.reversed_at is null where r.import_batch_id=p_batch_id and s.import_batch_id is distinct from p_batch_id) then raise exception 'IMPORT_ROLLBACK_REQUIRES_EXTERNAL_SETTLEMENT_REVERSAL';end if;
 update public.settlements set reversed_at=now(),reversed_by=auth.uid(),reversal_reason='Rollback do lote de importação histórica' where organization_id=p_organization_id and import_batch_id=p_batch_id and reversed_at is null;
 update public.financial_entries e set deleted_at=now(),updated_by=auth.uid() from public.import_staging_rows r where r.import_batch_id=p_batch_id and r.organization_id=p_organization_id and r.financial_entry_id=e.id and e.organization_id=p_organization_id and e.source_type='IMPORTACAO' and e.deleted_at is null;get diagnostics affected=row_count;
 update public.import_staging_rows set resolution_status='ROLLED_BACK' where import_batch_id=p_batch_id and organization_id=p_organization_id and resolution_status='IMPORTED';
 update public.import_batches set status='REVERTIDO',reverted_by=auth.uid(),reverted_at=now() where id=p_batch_id;
 insert into public.audit_logs(organization_id,actor_user_id,entity_type,entity_id,action,new_data) values(p_organization_id,auth.uid(),'IMPORT_BATCH',p_batch_id,'IMPORT_ROLLED_BACK',jsonb_build_object('reverted_entries',affected,'surrogate_settlements_reversed',true));return affected;
end$$;
revoke all on function public.rollback_finagro_import(uuid,uuid) from public;grant execute on function public.rollback_finagro_import(uuid,uuid) to authenticated;
