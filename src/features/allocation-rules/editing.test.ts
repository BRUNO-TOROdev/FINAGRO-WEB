// @vitest-environment jsdom

import React from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { AllocationRuleForm } from "./allocation-rule-form";
import { allocationRuleFormInitial } from "./form-model";
import type { AllocationRule } from "@/types/database";

const rule: AllocationRule = {
  id: "10000000-0000-0000-0000-000000000001",
  organization_id: "10000000-0000-0000-0000-000000000010",
  crop_season_id: null,
  allocation_scope: "GENERAL",
  effective_from: "2026-11-01",
  effective_to: null,
  name: "Rateio Geral",
  description: null,
  is_active: true,
  created_at: "2026-11-01T00:00:00Z",
};

const farms = [
  { id: "20000000-0000-0000-0000-000000000001", name: "HS", is_active: true },
  { id: "20000000-0000-0000-0000-000000000002", name: "ESCONDIDA", is_active: true },
  { id: "20000000-0000-0000-0000-000000000003", name: "SANTO ÂNGELO", is_active: true },
];

const initial = allocationRuleFormInitial(rule, [
  { allocation_rule_id: rule.id, farm_id: farms[0].id, percentage: 45 },
  { allocation_rule_id: rule.id, farm_id: farms[1].id, percentage: "15.000000" },
  { allocation_rule_id: rule.id, farm_id: farms[2].id, percentage: 40 },
]);

afterEach(cleanup);

describe("allocation rule editing", () => {
  it("loads the existing GENERAL rule with validity and percentages", () => {
    render(React.createElement(AllocationRuleForm, { action: vi.fn(), farms, seasons: [], initial }));

    expect(screen.getByLabelText("Nome")).toHaveProperty("value", "Rateio Geral");
    expect(screen.getByLabelText("Tipo")).toHaveProperty("value", "GENERAL");
    expect(screen.getByLabelText("Tipo")).toHaveProperty("disabled", true);
    expect(screen.queryByLabelText("Safra")).toBeNull();
    expect(screen.getByLabelText("Vigência inicial")).toHaveProperty("value", "2026-11-01");
    expect(screen.getByLabelText("Vigência final (opcional)")).toHaveProperty("value", "");
    expect(screen.getByLabelText(/^HS/)).toHaveProperty("value", "45");
    expect(screen.getByLabelText(/^ESCONDIDA/)).toHaveProperty("value", "15,000000");
    expect(screen.getByLabelText(/^SANTO ÂNGELO/)).toHaveProperty("value", "40");
    expect(screen.getByText("100,00%")).toBeTruthy();
    expect(screen.getByLabelText("Ativa")).toHaveProperty("checked", true);
    expect(screen.getByRole("button", { name: "Salvar alterações" })).toBeTruthy();
  });

  it("keeps activation blocked when an edited total differs from 100%", () => {
    render(React.createElement(AllocationRuleForm, { action: vi.fn(), farms, seasons: [], initial }));

    fireEvent.change(screen.getByLabelText(/^HS/), { target: { value: "44" } });

    expect(screen.getByText("99,00%")).toBeTruthy();
    expect(screen.getByLabelText("Ativa")).toHaveProperty("disabled", true);
    expect(screen.getByLabelText("Ativa")).toHaveProperty("checked", false);
  });
});
