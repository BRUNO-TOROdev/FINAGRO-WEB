import { expect, test } from "@playwright/test";

test("sessão inexistente em /app é redirecionada para login", async ({ request }) => {
  const response = await request.get("/app", { maxRedirects: 0 });
  expect(response.status()).toBeGreaterThanOrEqual(300);
  expect(response.status()).toBeLessThan(400);
  expect(response.headers().location).toContain("/login?next=%2Fapp");
});

test("login local responde e apresenta o formulário de autenticação", async ({ request }) => {
  const response = await request.get("/login");
  expect(response.ok()).toBe(true);
  const html = await response.text();
  expect(html).toContain("Acesse sua conta");
  expect(html).toContain('name="email"');
  expect(html).toContain('name="password"');
});

test("dashboard de organização exige autenticação", async ({ request }) => {
  const response = await request.get("/app/tenant-inexistente", { maxRedirects: 0 });
  expect(response.status()).toBeGreaterThanOrEqual(300);
  expect(response.status()).toBeLessThan(400);
  expect(response.headers().location).toContain("/login");
});

test("rota de financiamentos preserva a fronteira autenticada", async ({ request }) => {
  const response = await request.get("/app/tenant-inexistente/financiamentos", { maxRedirects: 0 });
  expect(response.status()).toBeGreaterThanOrEqual(300);
  expect(response.status()).toBeLessThan(400);
  expect(response.headers().location).toContain("/login");
});

test("rota de orçamentos preserva a fronteira autenticada", async ({ request }) => {
  const response = await request.get("/app/tenant-inexistente/orcamentos", { maxRedirects: 0 });
  expect(response.status()).toBeGreaterThanOrEqual(300);
  expect(response.status()).toBeLessThan(400);
  expect(response.headers().location).toContain("/login");
});

test("rota da DRE preserva a fronteira autenticada", async ({ request }) => {
  const response = await request.get("/app/tenant-inexistente/relatorios/dre", { maxRedirects: 0 });
  expect(response.status()).toBeGreaterThanOrEqual(300);
  expect(response.status()).toBeLessThan(400);
  expect(response.headers().location).toContain("/login");
});

test("rota da DRE Safra preserva a fronteira autenticada", async ({ request }) => {
  const response = await request.get("/app/tenant-inexistente/relatorios/dre-safra", { maxRedirects: 0 });
  expect(response.status()).toBeGreaterThanOrEqual(300);
  expect(response.status()).toBeLessThan(400);
  expect(response.headers().location).toContain("/login");
});

test("rota do Fluxo de Caixa preserva a fronteira autenticada", async ({ request }) => {
  const response = await request.get("/app/tenant-inexistente/relatorios/fluxo-de-caixa", { maxRedirects: 0 });
  expect(response.status()).toBeGreaterThanOrEqual(300);
  expect(response.status()).toBeLessThan(400);
  expect(response.headers().location).toContain("/login");
});

test("rota de Projetado × Realizado preserva a fronteira autenticada", async ({ request }) => {
  const response = await request.get("/app/tenant-inexistente/relatorios/projetado-realizado", { maxRedirects: 0 });
  expect(response.status()).toBeGreaterThanOrEqual(300);
  expect(response.status()).toBeLessThan(400);
  expect(response.headers().location).toContain("/login");
});
