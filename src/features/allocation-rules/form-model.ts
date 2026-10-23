import type { AllocationRule } from "@/types/database";

export type AllocationRuleItemValue = {
  allocation_rule_id: string;
  farm_id: string;
  percentage: string | number;
};

export type AllocationRuleFormInitial = {
  name: string;
  scope: "SEASONAL" | "GENERAL";
  cropSeasonId: string | null;
  effectiveFrom: string | null;
  effectiveTo: string | null;
  description: string;
  isActive: boolean;
  percentages: Record<string, string>;
};

export function allocationRuleFormInitial(
  rule: AllocationRule,
  items: AllocationRuleItemValue[],
): AllocationRuleFormInitial {
  return {
    name: rule.name,
    scope: rule.allocation_scope,
    cropSeasonId: rule.crop_season_id,
    effectiveFrom: rule.effective_from,
    effectiveTo: rule.effective_to,
    description: rule.description ?? "",
    isActive: rule.is_active,
    percentages: Object.fromEntries(
      items
        .filter((item) => item.allocation_rule_id === rule.id)
        .map((item) => [item.farm_id, String(item.percentage).replace(".", ",")]),
    ),
  };
}
