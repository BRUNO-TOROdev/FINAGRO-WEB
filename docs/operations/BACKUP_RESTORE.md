# FINAGRO Web V1 — backup e restore

## Política mínima

- Habilitar backups automáticos/PITR do Supabase antes do piloto.
- Frequência mínima: diária; para operação financeira, preferir PITR contínuo.
- Retenção mínima sugerida: 30 dias, sujeita à política jurídica/contratual.
- Gerar backup lógico adicional antes de migrations e releases materiais.
- Criptografar, restringir acesso e registrar o responsável por cada restore.
- Nunca armazenar dumps reais no Git ou em diretório público da aplicação.

## Teste obrigatório de recuperação

O restore ocorre em projeto/banco isolado e descartável, nunca sobre produção.

1. Selecione backup de staging com dados exclusivamente sintéticos.
2. Restaure em instância isolada com PostgreSQL da mesma major.
3. Confirme as 22 migrations e o schema esperado.
4. Confirme tabelas, constraints, índices, RLS e policies.
5. Teste usuários autenticados de duas organizações e o isolamento.
6. Confirme dados sintéticos e reconciliação financeira conhecida.
7. Registre data, backup, ambiente, duração, RPO/RTO e PASS/FAIL sem PII.
8. Destrua com segurança a instância temporária ao final.

## Critérios de aprovação

- Schema e migrations presentes.
- RLS ativa e ataques cross-tenant recusados.
- Dados sintéticos íntegros e valores `NUMERIC` exatos.
- Aplicação autentica e lê a organização restaurada.
- Procedimento repetível e responsável identificado.

Sem um restore real aprovado em ambiente isolado, backup permanece **BLOCKER EXTERNO**.
