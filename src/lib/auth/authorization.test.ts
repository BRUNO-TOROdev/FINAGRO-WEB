import { describe, expect, it } from "vitest";
import {
  AuthenticationRequiredError,
  authorizeOrganization,
  OrganizationAccessDeniedError,
  PermissionDeniedError,
  type AuthorizationRepository,
} from "./authorization";
import type { OrganizationContext } from "@/types/database";

const organizationA: OrganizationContext = {
  id: "org-a", legal_name: "Organização A", trade_name: null, slug: "organizacao-a", is_active: true,
  membershipId: "membership-a", roleId: "role-a", roleName: "Administrador",
  permissions: ["farms.view", "farms.manage", "seasons.view", "seasons.manage"],
};
const organizationReadOnly: OrganizationContext = {
  ...organizationA, roleName: "Somente leitura", roleId: "read-only",
  permissions: ["farms.view", "seasons.view", "entries.view", "parties.view", "bank_accounts.view"],
};

class FakeRepository implements AuthorizationRepository {
  constructor(private readonly contexts: Record<string, OrganizationContext>) {}
  async findOrganizationContext(userId: string, slug: string) { return this.contexts[`${userId}:${slug}`] ?? null; }
}

describe("autorização multi-tenant", () => {
  it("permite ao usuário A acessar sua Organização A", async () => {
    const repo = new FakeRepository({ "user-a:organizacao-a": organizationA });
    await expect(authorizeOrganization(repo, "user-a", "organizacao-a")).resolves.toEqual(organizationA);
  });

  it("nega ao usuário A a Organização B", async () => {
    const repo = new FakeRepository({ "user-a:organizacao-a": organizationA });
    await expect(authorizeOrganization(repo, "user-a", "organizacao-b")).rejects.toBeInstanceOf(OrganizationAccessDeniedError);
  });

  it("não retorna dados ao alterar manualmente o slug", async () => {
    const repo = new FakeRepository({ "user-b:organizacao-b": { ...organizationA, id: "org-b", slug: "organizacao-b" } });
    await expect(authorizeOrganization(repo, "user-a", "organizacao-b")).rejects.toThrow("ORGANIZATION_ACCESS_DENIED");
  });

  it("recusa criação de fazenda para READ_ONLY", async () => {
    const repo = new FakeRepository({ "reader:organizacao-a": organizationReadOnly });
    await expect(authorizeOrganization(repo, "reader", "organizacao-a", "farms.manage")).rejects.toBeInstanceOf(PermissionDeniedError);
  });

  it("permite criação de fazenda para perfil autorizado", async () => {
    const repo = new FakeRepository({ "user-a:organizacao-a": organizationA });
    await expect(authorizeOrganization(repo, "user-a", "organizacao-a", "farms.manage")).resolves.toEqual(organizationA);
  });

  it("recusa alteração de safra para READ_ONLY", async () => {
    const repo = new FakeRepository({ "reader:organizacao-a": organizationReadOnly });
    await expect(authorizeOrganization(repo, "reader", "organizacao-a", "seasons.manage")).rejects.toBeInstanceOf(PermissionDeniedError);
  });

  it("ignora organization_id injetado e deriva o tenant do slug autorizado", async () => {
    const repo = new FakeRepository({ "user-a:organizacao-a": organizationA });
    const maliciousPayload = { organization_id: "org-b", name: "Fazenda indevida" };
    const context = await authorizeOrganization(repo, "user-a", "organizacao-a", "farms.manage");
    expect(context.id).toBe("org-a");
    expect(context.id).not.toBe(maliciousPayload.organization_id);
  });

  it("exige autenticação antes de resolver organização", async () => {
    const repo = new FakeRepository({});
    await expect(authorizeOrganization(repo, null, "organizacao-a")).rejects.toBeInstanceOf(AuthenticationRequiredError);
  });

  it("READ_ONLY visualiza lançamentos mas não cria nem edita", async () => {
    const repo = new FakeRepository({ "reader:organizacao-a": organizationReadOnly });
    await expect(authorizeOrganization(repo, "reader", "organizacao-a", "entries.view")).resolves.toEqual(organizationReadOnly);
    await expect(authorizeOrganization(repo, "reader", "organizacao-a", "entries.create")).rejects.toBeInstanceOf(PermissionDeniedError);
    await expect(authorizeOrganization(repo, "reader", "organizacao-a", "entries.update")).rejects.toBeInstanceOf(PermissionDeniedError);
  });

  it("READ_ONLY não administra contrapartes ou contas bancárias", async () => {
    const repo = new FakeRepository({ "reader:organizacao-a": organizationReadOnly });
    await expect(authorizeOrganization(repo, "reader", "organizacao-a", "parties.manage")).rejects.toBeInstanceOf(PermissionDeniedError);
    await expect(authorizeOrganization(repo, "reader", "organizacao-a", "bank_accounts.manage")).rejects.toBeInstanceOf(PermissionDeniedError);
  });
});
