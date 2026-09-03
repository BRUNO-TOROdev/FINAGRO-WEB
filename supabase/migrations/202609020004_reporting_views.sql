-- FINAGRO Web — Reporting Views v0.2
-- security_invoker ensures underlying RLS policies remain effective.

create or replace view public.v_entry_allocated_amounts
with (security_invoker = true)
as
select
    e.organization_id,
    e.id as financial_entry_id,
    a.farm_id,
    e.crop_season_id,
    e.chart_account_id,
    e.counterparty_id,
    e.issue_date,
    e.due_date,
    e.status,
    e.entry_direction,
    e.amount as entry_amount,
    a.percentage as allocation_percentage,
    a.allocated_amount,
    case
        when e.entry_direction = 'SAIDA' then -a.allocated_amount
        else a.allocated_amount
    end as signed_allocated_amount,
    date_trunc('month', e.issue_date)::date as dre_month,
    date_trunc('month', e.due_date)::date as cashflow_due_month,
    a.allocation_rule_id,
    a.snapshot_rule_name,
    a.snapshot_crop_season_name
from public.financial_entries e
join public.entry_allocations a
  on a.financial_entry_id = e.id
 and a.organization_id = e.organization_id
where e.deleted_at is null;

create or replace view public.v_dre_fact
with (security_invoker = true)
as
select
    v.organization_id,
    v.financial_entry_id,
    v.farm_id,
    v.crop_season_id,
    v.chart_account_id,
    c.parent_id as parent_chart_account_id,
    c.code as chart_account_code,
    c.name as chart_account_name,
    c.managerial_type,
    c.nature,
    v.issue_date,
    v.dre_month as period_month,
    v.entry_direction,
    v.status,
    v.allocated_amount,
    v.signed_allocated_amount
from public.v_entry_allocated_amounts v
join public.chart_accounts c
  on c.id = v.chart_account_id
 and c.organization_id = v.organization_id
where c.participates_dre = true;

create or replace view public.v_cashflow_due_fact
with (security_invoker = true)
as
select
    v.organization_id,
    v.financial_entry_id,
    v.farm_id,
    v.crop_season_id,
    v.chart_account_id,
    c.code as chart_account_code,
    c.name as chart_account_name,
    c.managerial_type,
    v.due_date,
    v.cashflow_due_month as period_month,
    v.entry_direction,
    v.status,
    v.allocated_amount,
    v.signed_allocated_amount
from public.v_entry_allocated_amounts v
join public.chart_accounts c
  on c.id = v.chart_account_id
 and c.organization_id = v.organization_id
where c.participates_cashflow = true;

create or replace view public.v_settlement_cash_movements
with (security_invoker = true)
as
select
    s.organization_id,
    s.id as settlement_id,
    s.financial_entry_id,
    s.bank_account_id,
    s.settled_at,
    date_trunc('month', s.settled_at)::date as period_month,
    e.entry_direction,
    s.amount,
    case
        when e.entry_direction = 'SAIDA' then -s.amount
        else s.amount
    end as signed_amount,
    e.chart_account_id,
    e.crop_season_id,
    e.counterparty_id
from public.settlements s
join public.financial_entries e
  on e.id = s.financial_entry_id
 and e.organization_id = s.organization_id
where s.reversed_at is null
  and e.deleted_at is null;

create or replace view public.v_budget_allocated_amounts
with (security_invoker = true)
as
select
    b.organization_id,
    b.id as budget_id,
    b.budget_type,
    b.status as budget_status,
    bi.id as budget_item_id,
    bi.period_month,
    bi.chart_account_id,
    coalesce(bi.crop_season_id, b.crop_season_id) as crop_season_id,
    ba.farm_id,
    ba.percentage as allocation_percentage,
    ba.allocated_amount,
    ba.allocation_rule_id,
    ba.snapshot_rule_name
from public.budgets b
join public.budget_items bi
  on bi.budget_id = b.id
 and bi.organization_id = b.organization_id
join public.budget_item_allocations ba
  on ba.budget_item_id = bi.id
 and ba.organization_id = bi.organization_id;

-- Convenience aggregate for monthly projected x realized DRE.
-- Hierarchical presentation/subtotals remain application/report-service responsibility.
create or replace view public.v_dre_projected_vs_realized_monthly
with (security_invoker = true)
as
with realized as (
    select
        organization_id,
        farm_id,
        crop_season_id,
        chart_account_id,
        period_month,
        sum(allocated_amount) as realized_amount
    from public.v_dre_fact
    group by organization_id, farm_id, crop_season_id, chart_account_id, period_month
), projected as (
    select
        organization_id,
        farm_id,
        crop_season_id,
        chart_account_id,
        period_month,
        sum(allocated_amount) as projected_amount
    from public.v_budget_allocated_amounts
    where budget_type = 'DRE'
      and budget_status = 'ATIVO'
    group by organization_id, farm_id, crop_season_id, chart_account_id, period_month
), keys as (
    select organization_id, farm_id, crop_season_id, chart_account_id, period_month from realized
    union
    select organization_id, farm_id, crop_season_id, chart_account_id, period_month from projected
)
select
    k.organization_id,
    k.farm_id,
    k.crop_season_id,
    k.chart_account_id,
    k.period_month,
    coalesce(p.projected_amount, 0)::numeric(18,2) as projected_amount,
    coalesce(r.realized_amount, 0)::numeric(18,2) as realized_amount,
    (coalesce(r.realized_amount, 0) - coalesce(p.projected_amount, 0))::numeric(18,2) as variance_amount,
    case
        when coalesce(p.projected_amount, 0) = 0 then null
        else round(
            ((coalesce(r.realized_amount, 0) - p.projected_amount) / p.projected_amount) * 100,
            4
        )
    end as variance_percent
from keys k
left join realized r
  on r.organization_id = k.organization_id
 and r.farm_id = k.farm_id
 and r.crop_season_id is not distinct from k.crop_season_id
 and r.chart_account_id = k.chart_account_id
 and r.period_month = k.period_month
left join projected p
  on p.organization_id = k.organization_id
 and p.farm_id = k.farm_id
 and p.crop_season_id is not distinct from k.crop_season_id
 and p.chart_account_id = k.chart_account_id
 and p.period_month = k.period_month;
