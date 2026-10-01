-- FINAGRO Web — tenant-safe dashboard composition over homologated reporting engines.

create or replace function public.get_management_dashboard(
  p_organization_id uuid,
  p_start_month date,
  p_end_month date,
  p_farm_id uuid default null,
  p_dre_basis text default 'DRE_COMPETENCIA',
  p_budget_version_id uuid default null,
  p_crop_season_id uuid default null,
  p_second_crop_season_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  dre_result jsonb;
  cash_result jsonb;
  dre_comparison jsonb;
  cash_comparison jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_organization_id, 'reports.view') then
    raise exception 'PERMISSION_DENIED';
  end if;
  if p_dre_basis not in ('DRE_COMPETENCIA', 'DRE_SAFRA') then
    raise exception 'INVALID_DRE_BASIS';
  end if;
  if date_trunc('month', p_start_month)::date <> p_start_month
     or date_trunc('month', p_end_month)::date <> p_end_month
     or p_end_month < p_start_month then
    raise exception 'INVALID_DASHBOARD_PERIOD';
  end if;
  if p_farm_id is not null and not exists (
    select 1 from public.farms
    where id = p_farm_id and organization_id = p_organization_id and is_active
  ) then raise exception 'FARM_NOT_FOUND_IN_ORGANIZATION'; end if;

  if p_dre_basis = 'DRE_SAFRA' then
    if p_crop_season_id is null or p_second_crop_season_id is null then
      raise exception 'CROP_SEASONS_REQUIRED';
    end if;
    dre_result := public.get_realized_dre_crop_season(
      p_organization_id, p_crop_season_id, p_second_crop_season_id, p_farm_id, null
    );
  else
    dre_result := public.get_realized_dre(
      p_organization_id, p_start_month, p_end_month, p_farm_id, null
    );
  end if;

  cash_result := public.get_realized_cash_flow(
    p_organization_id, p_start_month, p_end_month, p_farm_id, null
  );

  if p_budget_version_id is not null then
    dre_comparison := public.get_projected_vs_actual(
      p_organization_id, p_budget_version_id, p_dre_basis,
      p_start_month, p_end_month, p_farm_id,
      p_crop_season_id, p_second_crop_season_id, null, null
    );
    cash_comparison := public.get_projected_vs_actual(
      p_organization_id, p_budget_version_id, 'DFC_VENCIMENTO',
      p_start_month, p_end_month, p_farm_id, null, null, null, null
    );
  end if;

  return jsonb_build_object(
    'context', jsonb_build_object(
      'organization_id', p_organization_id,
      'start_month', p_start_month,
      'end_month', p_end_month,
      'farm_id', p_farm_id,
      'dre_basis', p_dre_basis,
      'budget_version_id', p_budget_version_id,
      'crop_season_id', p_crop_season_id,
      'second_crop_season_id', p_second_crop_season_id
    ),
    'dre', dre_result,
    'cash_flow', cash_result,
    'comparison_dre', dre_comparison,
    'comparison_cash_flow', cash_comparison
  );
end;
$$;

revoke all on function public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid) from public;
grant execute on function public.get_management_dashboard(uuid,date,date,uuid,text,uuid,uuid,uuid) to authenticated;

