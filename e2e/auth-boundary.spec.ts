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
