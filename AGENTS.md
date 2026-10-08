# AGENTS.md — FINAGRO Web

## Missão
Construir um SaaS financeiro rural confiável. Priorize correção financeira, isolamento multi-tenant, auditabilidade e simplicidade de uso acima de velocidade ou efeitos visuais.

## Regras permanentes
1. Nunca altere regra financeira sem atualizar documentação e testes.
2. Nunca use `float`, `number` ou ponto flutuante para cálculo monetário definitivo.
3. PostgreSQL `NUMERIC` é a fonte de precisão financeira.
4. Toda entidade operacional pertence a `organization_id`.
5. Nunca confie apenas em filtro de frontend para tenant isolation.
6. Toda ação protegida deve validar sessão + membership + permissão server-side.
7. Nunca exponha Supabase service role ao browser.
8. Status financeiro: somente `PENDENTE`, `AGENDADO`, `PAGO`.
9. `PAGO` exige liquidação integral.
10. `GERAL` não é fazenda nem Safra; despesas compartilhadas usam regra `GENERAL` da organização, vigente na data e independente de Safra.
11. Rateio aplicado é snapshot histórico e não muda retroativamente.
12. Mais de uma fazenda em um lançamento exige regra formal de rateio.
13. Plano de contas pertence à organização; FINAGRO é template inicial, não estrutura fixa.
14. DRE MVP usa data de emissão.
15. Fluxo previsto MVP usa data de vencimento.
16. Liquidações são revertidas, não editadas/destruídas.
17. Não faça hard delete de lançamentos financeiros pela aplicação.
18. Alterações críticas precisam de auditoria.
19. Interface e textos devem ser em português do Brasil.
20. Datas na UI: DD/MM/YYYY; moeda: BRL/R$.

## Forma de trabalho
- Uma feature por branch/PR lógico.
- Antes de codificar, leia PRD, decisões e migrations.
- Crie teste antes ou junto da implementação de regra crítica.
- Não “simplifique” fórmula/regra legada sem aprovação explícita.
- Não criar módulo fora do escopo da etapa atual.
- Se houver ambiguidade de negócio, documente em `docs/OPEN_QUESTIONS.md` em vez de inventar comportamento.

## Definition of Done
Uma feature financeira só está pronta se tiver:
- autorização server-side;
- proteção RLS aplicável;
- validação Zod;
- tratamento de erro;
- testes positivos e negativos;
- teste cross-tenant quando houver dados tenant-owned;
- auditoria quando crítica;
- documentação de regra relevante.
