-- FINAGRO Web — financing and loan management.
-- Contract values are informational; only linked financial entries affect cash flow.

alter table public.financing_contracts
  add column description text,
  add column crop_season_id uuid,
  add column farm_id uuid,
  add column allocation_rule_id uuid,
  add column amortization_type text not null default 'CRONOGRAMA_INFORMADO'
    check (amortization_type in ('SAC','PRICE','OUTRO','CRONOGRAMA_INFORMADO')),
  add column interest_rate numeric(12,6) check (interest_rate is null or interest_rate >= 0),
  add column interest_rate_period text,
  add column interest_rate_type text check (interest_rate_type is null or interest_rate_type in ('PREFIXADO','POS_FIXADO')),
  add column indexer text,
  add column has_grace_period boolean not null default false,
  add column grace_period_ends_on date,
  add column credit_chart_account_id uuid,
  add column principal_chart_account_id uuid,
  add column interest_chart_account_id uuid,
  add column charges_chart_account_id uuid,
  add constraint financing_contracts_season_org_fkey foreign key (crop_season_id,organization_id) references public.crop_seasons(id,organization_id),
  add constraint financing_contracts_farm_org_fkey foreign key (farm_id,organization_id) references public.farms(id,organization_id),
  add constraint financing_contracts_rule_org_fkey foreign key (allocation_rule_id,organization_id) references public.allocation_rules(id,organization_id),
  add constraint financing_contracts_credit_account_org_fkey foreign key (credit_chart_account_id,organization_id) references public.chart_accounts(id,organization_id),
  add constraint financing_contracts_principal_account_org_fkey foreign key (principal_chart_account_id,organization_id) references public.chart_accounts(id,organization_id),
  add constraint financing_contracts_interest_account_org_fkey foreign key (interest_chart_account_id,organization_id) references public.chart_accounts(id,organization_id),
  add constraint financing_contracts_charges_account_org_fkey foreign key (charges_chart_account_id,organization_id) references public.chart_accounts(id,organization_id),
  add constraint financing_contracts_allocation_choice check (not (farm_id is not null and allocation_rule_id is not null)),
  add constraint financing_contracts_grace_period check (has_grace_period or grace_period_ends_on is null);

create table public.financing_installment_charges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  financing_installment_id uuid not null,
  charge_type text not null check (charge_type in ('TARIFA','SEGURO','OUTRO')),
  description text,
  amount numeric(18,2) not null check (amount > 0),
  chart_account_id uuid not null,
  financial_entry_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id,organization_id),
  unique(financing_installment_id,charge_type),
  foreign key(financing_installment_id,organization_id) references public.financing_installments(id,organization_id) on delete cascade,
  foreign key(chart_account_id,organization_id) references public.chart_accounts(id,organization_id),
  foreign key(financial_entry_id,organization_id) references public.financial_entries(id,organization_id)
);

alter table public.financing_installment_charges enable row level security;
create policy financing_installment_charges_read on public.financing_installment_charges for select to authenticated
  using(private.has_permission(organization_id,'financing.view'));
create policy financing_installment_charges_insert on public.financing_installment_charges for insert to authenticated
  with check(private.has_permission(organization_id,'financing.manage'));
create policy financing_installment_charges_update on public.financing_installment_charges for update to authenticated
  using(private.has_permission(organization_id,'financing.manage')) with check(private.has_permission(organization_id,'financing.manage'));

create trigger trg_financing_installment_charges_updated_at before update on public.financing_installment_charges
  for each row execute function private.set_updated_at();
create trigger trg_financing_installment_charges_audit after insert or update or delete on public.financing_installment_charges
  for each row execute function private.audit_row_change();

create index idx_financing_contracts_org_issued on public.financing_contracts(organization_id,issued_on desc);
create index idx_financing_installments_contract_due on public.financing_installments(organization_id,financing_contract_id,due_date);
create index idx_financing_charges_installment on public.financing_installment_charges(organization_id,financing_installment_id);

create or replace function private.guard_financing_contract() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then raise exception 'FINANCING_ORGANIZATION_IS_IMMUTABLE'; end if;
  if new.allocation_rule_id is not null and not exists(select 1 from public.allocation_rules r where r.id=new.allocation_rule_id and r.organization_id=new.organization_id and r.is_active and r.crop_season_id=new.crop_season_id) then raise exception 'ACTIVE_ALLOCATION_RULE_MUST_MATCH_FINANCING_SEASON'; end if;
  if new.farm_id is not null and not exists(select 1 from public.farms f where f.id=new.farm_id and f.organization_id=new.organization_id and f.is_active) then raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION'; end if;
  if tg_op='UPDATE' and (old.credit_entry_id is not null or exists(select 1 from public.financing_installments i where i.financing_contract_id=old.id)) and
    (new.contract_number is distinct from old.contract_number or new.contracted_amount is distinct from old.contracted_amount or new.installment_count is distinct from old.installment_count or new.creditor_party_id is distinct from old.creditor_party_id or new.bank_account_id is distinct from old.bank_account_id or new.crop_season_id is distinct from old.crop_season_id or new.farm_id is distinct from old.farm_id or new.allocation_rule_id is distinct from old.allocation_rule_id)
  then raise exception 'FINANCING_CONTRACT_WITH_MOVEMENTS_IS_IMMUTABLE'; end if;
  return new;
end$$;
create trigger trg_financing_contract_guard before insert or update on public.financing_contracts for each row execute function private.guard_financing_contract();

create or replace function public.create_financing_contract_with_schedule(
 p_organization_id uuid,p_creditor_party_id uuid,p_contract_number text,p_description text,p_contracted_amount numeric,
 p_issued_on date,p_credit_date date,p_installment_count integer,p_bank_account_id uuid,p_crop_season_id uuid,
 p_farm_id uuid,p_allocation_rule_id uuid,p_amortization_type text,p_interest_rate numeric,p_interest_rate_period text,
 p_interest_rate_type text,p_indexer text,p_has_grace_period boolean,p_grace_period_ends_on date,p_notes text,
 p_credit_amount numeric,p_credit_chart_account_id uuid,p_principal_chart_account_id uuid,p_interest_chart_account_id uuid,
 p_charges_chart_account_id uuid,p_allow_principal_difference boolean,p_schedule jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare c_id uuid;i_id uuid;e_id uuid;item jsonb;charge jsonb;n int:=0;principal_total numeric;interest numeric;principal numeric;charges_total numeric;mode text;charge_account uuid;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if not private.has_permission(p_organization_id,'financing.manage') or not private.has_permission(p_organization_id,'entries.create') then raise exception 'PERMISSION_DENIED'; end if;
 if p_contracted_amount is null or p_contracted_amount<=0 then raise exception 'FINANCING_PRINCIPAL_MUST_BE_POSITIVE'; end if;
 if p_installment_count is null or p_installment_count<=0 or jsonb_typeof(p_schedule)<>'array' or jsonb_array_length(p_schedule)<>p_installment_count then raise exception 'FINANCING_SCHEDULE_INCOMPLETE'; end if;
 if p_amortization_type not in ('SAC','PRICE','OUTRO','CRONOGRAMA_INFORMADO') then raise exception 'INVALID_AMORTIZATION_TYPE'; end if;
 if not exists(select 1 from public.parties p where p.id=p_creditor_party_id and p.organization_id=p_organization_id and p.is_active) then raise exception 'ACTIVE_CREDITOR_NOT_FOUND_IN_ORGANIZATION'; end if;
 if p_bank_account_id is not null and not exists(select 1 from public.bank_accounts b where b.id=p_bank_account_id and b.organization_id=p_organization_id and b.is_active) then raise exception 'ACTIVE_BANK_ACCOUNT_NOT_FOUND_IN_ORGANIZATION'; end if;
 if p_crop_season_id is not null and not exists(select 1 from public.crop_seasons s where s.id=p_crop_season_id and s.organization_id=p_organization_id and s.is_active) then raise exception 'ACTIVE_CROP_SEASON_NOT_FOUND_IN_ORGANIZATION'; end if;
 if (p_farm_id is null)=(p_allocation_rule_id is null) then raise exception 'FINANCING_REQUIRES_FARM_OR_ALLOCATION_RULE'; end if;
 if p_allocation_rule_id is not null and not exists(select 1 from public.allocation_rules r where r.id=p_allocation_rule_id and r.organization_id=p_organization_id and r.is_active and r.crop_season_id=p_crop_season_id) then raise exception 'ACTIVE_ALLOCATION_RULE_MUST_MATCH_FINANCING_SEASON'; end if;
 if p_farm_id is not null and not exists(select 1 from public.farms f where f.id=p_farm_id and f.organization_id=p_organization_id and f.is_active) then raise exception 'ACTIVE_FARM_NOT_FOUND_IN_ORGANIZATION'; end if;
 if not exists(select 1 from public.chart_accounts a where a.id=p_principal_chart_account_id and a.organization_id=p_organization_id and a.is_active) then raise exception 'ACTIVE_PRINCIPAL_ACCOUNT_NOT_FOUND_IN_ORGANIZATION'; end if;
 select coalesce(sum((x->>'principal')::numeric),0) into principal_total from jsonb_array_elements(p_schedule)x;
 if principal_total<>p_contracted_amount and not coalesce(p_allow_principal_difference,false) then raise exception 'SCHEDULED_PRINCIPAL_MUST_MATCH_CONTRACT'; end if;
 if exists(select 1 from jsonb_array_elements(p_schedule)x where (x->>'number') is null or (x->>'due_date') is null or coalesce((x->>'principal')::numeric,0)<0 or coalesce((x->>'interest')::numeric,0)<0) then raise exception 'INVALID_FINANCING_INSTALLMENT'; end if;
 if (select count(distinct (x->>'number')::int) from jsonb_array_elements(p_schedule)x)<>p_installment_count or (select min((x->>'number')::int) from jsonb_array_elements(p_schedule)x)<>1 or (select max((x->>'number')::int) from jsonb_array_elements(p_schedule)x)<>p_installment_count then raise exception 'FINANCING_INSTALLMENT_NUMBERS_MUST_BE_CONTIGUOUS'; end if;
 mode:=case when p_farm_id is not null then 'DIRETA' else 'RATEIO' end;
 insert into public.financing_contracts(organization_id,creditor_party_id,bank_account_id,contract_number,description,issued_on,credit_date,contracted_amount,installment_count,notes,created_by,crop_season_id,farm_id,allocation_rule_id,amortization_type,interest_rate,interest_rate_period,interest_rate_type,indexer,has_grace_period,grace_period_ends_on,credit_chart_account_id,principal_chart_account_id,interest_chart_account_id,charges_chart_account_id)
 values(p_organization_id,p_creditor_party_id,p_bank_account_id,trim(p_contract_number),nullif(trim(p_description),''),p_issued_on,p_credit_date,p_contracted_amount,p_installment_count,nullif(trim(p_notes),''),auth.uid(),p_crop_season_id,p_farm_id,p_allocation_rule_id,p_amortization_type,p_interest_rate,nullif(trim(p_interest_rate_period),''),p_interest_rate_type,nullif(trim(p_indexer),''),coalesce(p_has_grace_period,false),p_grace_period_ends_on,p_credit_chart_account_id,p_principal_chart_account_id,p_interest_chart_account_id,p_charges_chart_account_id) returning id into c_id;
 if p_credit_amount is not null then
   if p_credit_amount<=0 or p_credit_date is null or p_bank_account_id is null or p_credit_chart_account_id is null then raise exception 'CREDIT_ENTRY_REQUIRES_AMOUNT_DATE_BANK_AND_ACCOUNT'; end if;
   e_id:=public.save_financial_entry(p_organization_id,null,'ENTRADA','PENDENTE',p_credit_date,p_credit_date,p_contract_number,'Liberação de financiamento',coalesce(nullif(trim(p_description),''),'Entrada do financiamento '||p_contract_number),p_creditor_party_id,p_credit_chart_account_id,p_crop_season_id,null,p_bank_account_id,p_credit_amount,p_notes,mode,p_farm_id,p_allocation_rule_id);
   update public.financial_entries set source_type='FINANCIAMENTO' where id=e_id; update public.financing_contracts set credit_entry_id=e_id where id=c_id;
 end if;
 for item in select value from jsonb_array_elements(p_schedule) order by (value->>'number')::int loop
   n:=n+1; principal:=coalesce((item->>'principal')::numeric,0); interest:=coalesce((item->>'interest')::numeric,0);
   insert into public.financing_installments(organization_id,financing_contract_id,installment_number,due_date,principal_amount,interest_amount,other_charges_amount)
   values(p_organization_id,c_id,n,(item->>'due_date')::date,principal,interest,0) returning id into i_id;
   if principal>0 then e_id:=public.save_financial_entry(p_organization_id,null,'SAIDA','PENDENTE',p_issued_on,(item->>'due_date')::date,p_contract_number,'Principal de financiamento','Principal '||lpad(n::text,2,'0')||'/'||lpad(p_installment_count::text,2,'0')||' — '||p_contract_number,p_creditor_party_id,p_principal_chart_account_id,p_crop_season_id,null,p_bank_account_id,principal,p_notes,mode,p_farm_id,p_allocation_rule_id);update public.financial_entries set source_type='FINANCIAMENTO' where id=e_id;update public.financing_installments set principal_entry_id=e_id where id=i_id;end if;
   if interest>0 then if p_interest_chart_account_id is null then raise exception 'INTEREST_ACCOUNT_REQUIRED';end if;e_id:=public.save_financial_entry(p_organization_id,null,'SAIDA','PENDENTE',p_issued_on,(item->>'due_date')::date,p_contract_number,'Juros de financiamento','Juros '||lpad(n::text,2,'0')||'/'||lpad(p_installment_count::text,2,'0')||' — '||p_contract_number,p_creditor_party_id,p_interest_chart_account_id,p_crop_season_id,null,p_bank_account_id,interest,p_notes,mode,p_farm_id,p_allocation_rule_id);update public.financial_entries set source_type='FINANCIAMENTO' where id=e_id;update public.financing_installments set interest_entry_id=e_id where id=i_id;end if;
   charges_total:=0;
   for charge in select value from jsonb_array_elements(coalesce(item->'charges','[]'::jsonb)) loop
     if coalesce((charge->>'amount')::numeric,0)<=0 or coalesce(charge->>'type','') not in ('TARIFA','SEGURO','OUTRO') then raise exception 'INVALID_FINANCING_CHARGE';end if;
     charge_account:=coalesce(nullif(charge->>'chart_account_id','')::uuid,p_charges_chart_account_id);if charge_account is null then raise exception 'CHARGE_ACCOUNT_REQUIRED';end if;
     e_id:=public.save_financial_entry(p_organization_id,null,'SAIDA','PENDENTE',p_issued_on,(item->>'due_date')::date,p_contract_number,charge->>'type',initcap(lower(charge->>'type'))||' '||lpad(n::text,2,'0')||'/'||lpad(p_installment_count::text,2,'0')||' — '||p_contract_number,p_creditor_party_id,charge_account,p_crop_season_id,null,p_bank_account_id,(charge->>'amount')::numeric,p_notes,mode,p_farm_id,p_allocation_rule_id);update public.financial_entries set source_type='FINANCIAMENTO' where id=e_id;
     insert into public.financing_installment_charges(organization_id,financing_installment_id,charge_type,description,amount,chart_account_id,financial_entry_id) values(p_organization_id,i_id,charge->>'type',nullif(trim(charge->>'description'),''),(charge->>'amount')::numeric,charge_account,e_id);charges_total:=charges_total+(charge->>'amount')::numeric;
   end loop;
   update public.financing_installments set other_charges_amount=charges_total where id=i_id;
 end loop;
 set constraints all immediate;set constraints all deferred;return c_id;
end$$;

revoke all on function public.create_financing_contract_with_schedule(uuid,uuid,text,text,numeric,date,date,integer,uuid,uuid,uuid,uuid,text,numeric,text,text,text,boolean,date,text,numeric,uuid,uuid,uuid,uuid,boolean,jsonb) from public;
grant execute on function public.create_financing_contract_with_schedule(uuid,uuid,text,text,numeric,date,date,integer,uuid,uuid,uuid,uuid,text,numeric,text,text,text,boolean,date,text,numeric,uuid,uuid,uuid,uuid,boolean,jsonb) to authenticated;

create or replace view public.v_financing_contract_summary with(security_invoker=true) as
select c.organization_id,c.id,c.contract_number,c.description,c.issued_on,c.credit_date,c.contracted_amount,c.installment_count,c.crop_season_id,c.farm_id,c.allocation_rule_id,c.amortization_type,
 p.name creditor_name,coalesce(ce.amount,0)::numeric(18,2) received_amount,
 coalesce(sum(i.principal_amount),0)::numeric(18,2) scheduled_principal,
 coalesce(sum(i.interest_amount),0)::numeric(18,2) scheduled_interest,
 coalesce(sum(i.other_charges_amount),0)::numeric(18,2) scheduled_charges,
 coalesce(sum(ps.paid),0)::numeric(18,2) principal_paid,
 (c.contracted_amount-coalesce(sum(ps.paid),0))::numeric(18,2) principal_balance,
 min(i.due_date) filter(where coalesce(pb.open_amount,i.principal_amount)+coalesce(ib.open_amount,i.interest_amount)>0) next_due_date,
 case when count(i.id)=0 then 'RASCUNHO' when c.contracted_amount-coalesce(sum(ps.paid),0)=0 then 'QUITADO' else 'EM_ABERTO' end situation
from public.financing_contracts c
left join public.parties p on p.id=c.creditor_party_id and p.organization_id=c.organization_id
left join public.financial_entries ce on ce.id=c.credit_entry_id and ce.organization_id=c.organization_id
left join public.financing_installments i on i.financing_contract_id=c.id and i.organization_id=c.organization_id
left join lateral(select coalesce(sum(s.amount) filter(where s.reversed_at is null),0) paid from public.settlements s where s.financial_entry_id=i.principal_entry_id)ps on true
left join public.v_financial_entry_balances pb on pb.financial_entry_id=i.principal_entry_id and pb.organization_id=i.organization_id
left join public.v_financial_entry_balances ib on ib.financial_entry_id=i.interest_entry_id and ib.organization_id=i.organization_id
group by c.id,p.name,ce.amount;
grant select on public.v_financing_contract_summary to authenticated;
revoke execute on function private.guard_financing_contract() from public,authenticated;
