export type Organization = {
  id: string;
  legal_name: string;
  trade_name: string | null;
  slug: string;
  is_active: boolean;
};

export type OrganizationContext = Organization & {
  membershipId: string;
  roleId: string;
  roleName: string;
  permissions: string[];
};

export type Farm = {
  id: string;
  organization_id: string;
  name: string;
  internal_code: string | null;
  total_area_ha: string | null;
  is_active: boolean;
};

export type CropSeason = {
  id: string;
  organization_id: string;
  name: string;
  season_type: "PRINCIPAL" | "SAFRINHA" | "OUTRA";
  crop_name: string | null;
  starts_on: string | null;
  ends_on: string | null;
  is_closed: boolean;
  is_active: boolean;
};

export type ChartAccount = {
  id: string;
  organization_id: string;
  parent_id: string | null;
  code: string;
  name: string;
  level: number;
  managerial_type: "RECEITA" | "CUSTO" | "DESPESA" | "INVESTIMENTO" | "FINANCIAMENTO" | "TRANSFERENCIA" | "SALDO_INICIAL" | "OUTRO";
  nature: "ENTRADA" | "SAIDA" | "NEUTRA";
  participates_dre: boolean;
  participates_cashflow: boolean;
  requires_farm: boolean;
  allows_allocation: boolean;
  requires_crop_season: boolean;
  display_order: number;
  is_active: boolean;
};

export type AllocationRule = {
  id: string;
  organization_id: string;
  crop_season_id: string;
  name: string;
  description: string | null;
  is_active: boolean;
  created_at: string;
};

export type AppUser = { id: string; email?: string; user_metadata?: { full_name?: string } };

export type Party = { id: string; organization_id: string; name: string; tax_id: string | null; party_type: "FORNECEDOR" | "CLIENTE" | "AMBOS" | "BENEFICIARIO" | "OUTRO"; email: string | null; phone: string | null; is_active: boolean };
export type BankAccount = { id: string; organization_id: string; farm_id: string | null; bank_code: string | null; bank_name: string; branch_number: string | null; account_number: string; account_type: string | null; opening_balance: string; opening_balance_date: string | null; is_active: boolean };
export type PaymentMethod = { id: string; organization_id: string; name: string; is_active: boolean };
export type FinancialEntry = { id: string; organization_id: string; entry_direction: "ENTRADA" | "SAIDA"; status: "PENDENTE" | "AGENDADO" | "PAGO"; issue_date: string; due_date: string; document_number: string | null; document_name: string | null; description: string; counterparty_id: string | null; chart_account_id: string; crop_season_id: string | null; payment_method_id: string | null; planned_bank_account_id: string | null; amount: string; installment_plan_id: string | null; installment_number: number | null; installment_total: number | null; notes: string | null };
export type EntryAllocation = { id: string; farm_id: string; allocation_rule_id: string | null; percentage: string; allocated_amount: string; snapshot_rule_name: string | null; snapshot_crop_season_name: string | null };
export type InstallmentPlan = { id: string; organization_id: string; description: string; total_amount: string; installment_count: number; first_due_date: string | null; notes: string | null; created_at: string };
export type Settlement = { id: string; organization_id: string; financial_entry_id: string; bank_account_id: string; payment_method_id: string | null; settled_at: string; amount: string; reference: string | null; notes: string | null; created_by: string | null; reversed_at: string | null; reversed_by: string | null; reversal_reason: string | null; created_at: string };
