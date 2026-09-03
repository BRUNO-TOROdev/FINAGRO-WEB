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

export type AppUser = { id: string; email?: string; user_metadata?: { full_name?: string } };
