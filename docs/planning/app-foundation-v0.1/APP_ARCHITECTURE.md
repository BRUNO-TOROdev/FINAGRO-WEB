# FINAGRO Web — Arquitetura da Aplicação v0.1

## Objetivo da etapa
Criar a fundação do SaaS sem implementar ainda módulos financeiros completos. A aplicação deve nascer pronta para autenticação, multi-tenancy, seleção de organização, navegação por organização, permissões e consumo seguro do PostgreSQL/Supabase.

## Stack alvo
- Next.js + React + TypeScript
- Tailwind CSS
- shadcn/ui
- Supabase Auth + PostgreSQL + Storage
- Zod para validação
- Vitest para testes unitários/integrados
- Playwright para fluxos críticos E2E
- Vercel para deploy do app

## Princípio de segurança
O frontend nunca é a fronteira de segurança.

A autorização precisa existir em:
1. RLS PostgreSQL;
2. camada server-side da aplicação;
3. testes automatizados.

Nunca expor `SUPABASE_SERVICE_ROLE_KEY` ao navegador.

## Contexto de tenant
URL recomendada:

```text
/app/[organizationSlug]/...
```

O slug serve apenas para navegação. O backend deve resolver o slug para `organization_id` e confirmar que o usuário autenticado possui membership ativa nessa organização.

Não confiar em `organization_id` enviado livremente pelo cliente.

## Fluxo de autenticação
1. Usuário acessa `/login`.
2. Supabase Auth autentica.
3. Aplicação busca memberships ativas do usuário.
4. Se zero: apresentar onboarding/criação de organização quando permitido.
5. Se uma: redirecionar para a organização.
6. Se várias: tela de seleção de organização.
7. Layout server-side resolve contexto da organização a cada navegação protegida.

## Layout protegido
O layout interno deve:
- obter sessão no servidor;
- resolver membership;
- obter role/permissões do usuário;
- bloquear tenant não autorizado antes de renderizar conteúdo;
- fornecer apenas dados de navegação necessários ao cliente.

## Permissões
Menus podem ser ocultados por permissão para UX, mas isso não constitui autorização.

Exemplo:
- `entries.view` mostra menu Financeiro;
- `entries.create` habilita Novo Lançamento;
- `settlements.create` habilita Baixar;
- `entries.manage_paid` habilita alteração excepcional de PAGO.

Toda ação server-side deve validar novamente a permissão.

## Organização de domínio sugerida

```text
src/
  app/
    (public)/
      login/
    (protected)/
      select-organization/
      app/[organizationSlug]/
        layout.tsx
        page.tsx
        cadastros/
        financeiro/
        relatorios/
        configuracoes/

  components/
    ui/
    layout/
    forms/

  features/
    organizations/
    memberships/
    farms/
    crop-seasons/
    chart-accounts/
    allocation-rules/
    parties/
    bank-accounts/
    financial-entries/
    settlements/
    financing/
    budgets/
    reports/

  lib/
    supabase/
      client.ts
      server.ts
    auth/
      require-user.ts
      require-organization.ts
      require-permission.ts
    money/
    dates/
    errors/

  server/
    repositories/
    services/

  schemas/

  tests/
```

## Separação de responsabilidades
### UI
- captura intenção;
- apresenta validação amigável;
- nunca implementa regra financeira definitiva.

### Server actions / route handlers
- autenticação;
- autorização;
- validação Zod;
- chamada de serviço de domínio;
- tradução de erros do banco para mensagens de usuário.

### Serviços de domínio
Exemplos futuros:
- `createFinancialEntry()`
- `applyAllocationRule()`
- `settleEntry()`
- `reverseSettlement()`
- `generateInstallments()`

Serviço orquestra a operação, mas invariantes essenciais continuam protegidas pelo banco.

### Repositories
Isolam consultas e persistência. Toda função tenant-owned recebe contexto de organização já resolvido pelo servidor.

## Dinheiro
No navegador e no TypeScript não converter valores monetários para float para cálculo financeiro.

Sugestão de contrato:
- receber valor digitado como string pt-BR;
- normalizar no servidor;
- enviar decimal em string ao PostgreSQL;
- cálculos definitivos no banco/Decimal library quando necessário.

## Datas
- UI: `DD/MM/YYYY`.
- Banco: `date` para emissão/vencimento e `timestamptz` para eventos.
- Timezone da organização deve ser respeitado.

## Navegação inicial do MVP
- Visão Geral
- Financeiro
- Orçamento
- Financiamentos
- Relatórios
- Cadastros
- Configurações

Cadastros:
- Fazendas
- Safras
- Plano de Contas
- Contrapartes
- Bancos e Contas
- Formas de Pagamento

Configurações:
- Organização
- Regras de Rateio
- Usuários e Permissões
- Auditoria

## Primeira entrega visual
A primeira entrega NÃO deve possuir lógica de DRE ou lançamentos completos.

Deve conter:
1. login;
2. logout;
3. criação/seleção de organização;
4. shell da aplicação;
5. menu protegido por permissões;
6. cadastro de Fazenda;
7. cadastro de Safra;
8. usuários/perfis mínimos;
9. testes de tenant isolation da navegação e APIs.

Depois dessa fundação, Plano de Contas e Rateio entram como primeiro bloco de negócio.

## Critério de pronto desta etapa
- usuário não autenticado não acessa `/app`;
- usuário A não abre URL da organização B;
- organização ativa é resolvida server-side;
- permissões chegam do banco, não de array hardcoded no componente;
- service role jamais aparece no bundle cliente;
- logout invalida sessão;
- testes E2E cobrem dois usuários/dois tenants;
- `npm run lint`, `npm run typecheck` e testes ficam verdes.
