# Prompt para Codex — FINAGRO Web / Etapa Banco e Segurança

Você atuará como engenheiro sênior PostgreSQL/Supabase, especialista em SaaS multi-tenant, sistemas financeiros, RLS, testes de integração e segurança de dados.

## Contexto
O projeto FINAGRO Web transforma uma metodologia de gestão financeira rural originalmente construída em Excel em um SaaS multiempresa.

Leia integralmente antes de alterar qualquer arquivo:
- `docs/PRODUCT_SPEC.md`, quando existir;
- PRD funcional FINAGRO;
- arquitetura de dados FINAGRO;
- `docs/DECISIONS.md` deste pacote;
- todas as migrations existentes;
- `tests/TEST_PLAN.md`.

## Regras que NÃO podem ser reinterpretadas
1. Tenant = Organização; Organização != Fazenda.
2. Status financeiros permitidos: `PENDENTE`, `AGENDADO`, `PAGO`.
3. Dinheiro usa `NUMERIC/Decimal`, nunca float.
4. `GERAL` não é fazenda: é uma regra de rateio de despesas compartilhadas.
5. Regra de rateio pertence a uma Safra e precisa somar 100% para ficar ativa.
6. Ao aplicar rateio, gravar snapshot; alterar regra posteriormente não altera histórico.
7. Mais de uma fazenda em um lançamento exige regra formal de rateio.
8. Plano de contas é personalizado por organização; FINAGRO é apenas template inicial.
9. DRE MVP usa data de emissão.
10. Fluxo previsto MVP usa data de vencimento.
11. PAGO exige liquidação integral.
12. Liquidação não é apagada/corrigida: é revertida e substituída.
13. Nenhuma regra financeira crítica pode existir somente no frontend.
14. Nenhuma consulta pode depender de um filtro de `organization_id` apenas na UI.

## Sua tarefa — execute somente esta etapa
1. Inicialize/ajuste Supabase local no repositório.
2. Revise as migrations em `supabase/migrations` sem alterar as regras funcionais acima.
3. Corrija exclusivamente problemas reais de sintaxe, compatibilidade Supabase, segurança ou integridade identificados durante execução.
4. Execute migrations em banco local limpo.
5. Implemente testes automatizados para todos os casos P0 de `tests/TEST_PLAN.md`.
6. Implemente testes autenticados de RLS com no mínimo dois usuários e duas organizações.
7. Prove que usuário A não lê nem grava dados da Organização B.
8. Teste rateio 100%, 99,99%, snapshot histórico e arredondamento de centavos.
9. Teste liquidação integral, sobrepagamento, reversão e tentativa manual de marcar PAGO.
10. Teste FKs compostas cross-tenant.
11. Gere documentação das decisões técnicas que precisaram mudar.

## Requisitos de teste
- Todo teste precisa ser determinístico.
- Não usar IDs ou dados de produção.
- Não desabilitar RLS para fazer teste “passar”.
- Testar como usuários `authenticated`, não apenas como service role.
- Service role pode ser usado apenas para preparar fixtures quando necessário.
- Qualquer `SECURITY DEFINER` deve ter `search_path` seguro e testes de autorização.

## Critério de conclusão
Não desenvolva frontend nesta etapa.

Conclua somente quando:
- migrations rodam do zero sem erro;
- todos os testes P0 estão verdes;
- há teste explícito de isolamento cross-tenant;
- há teste de snapshot de rateio;
- há teste de consistência de status/liquidação;
- nenhuma regra financeira crítica está somente na aplicação;
- `supabase db reset` é reproduzível.

Ao terminar, apresente:
1. migrations executadas;
2. testes criados;
3. resultado dos testes;
4. problemas encontrados e correções feitas;
5. riscos remanescentes;
6. arquivos alterados;
7. commit sugerido.

Pare após esta etapa e aguarde revisão antes de criar autenticação visual ou telas financeiras.
