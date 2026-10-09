# FINAGRO Web V1 — runbook de incidente

## Severidade

- **SEV-1:** cross-tenant, credencial exposta, corrupção financeira ou indisponibilidade total.
- **SEV-2:** função financeira crítica indisponível ou resultado inconsistente sem corrupção confirmada.
- **SEV-3:** degradação localizada, falha visual ou operação com contorno seguro.

## Resposta

1. Registre horário, ambiente, release, impacto e responsável, sem PII ou payload financeiro.
2. Para possível vazamento/corrupção, suspenda escritas ou tráfego e preserve evidências.
3. Revogue e rotacione credenciais expostas no provedor de origem.
4. Verifique Vercel, Supabase e observabilidade por correlation/request ID.
5. Se o erro for somente da aplicação, promova o deployment anterior.
6. Se envolver schema/dados, não reverta migration manualmente; use correção forward-only ou restore isolado.
7. Valide Auth, RLS, cross-tenant, fluxo sintético e `/api/health` antes de reabrir.
8. Registre encerramento, impacto e prevenção; faça post-mortem de SEV-1/SEV-2.

## Cenários

- **Supabase indisponível:** health retorna 503 genérico; retire a aplicação de rotação.
- **Sessão expirada:** retorne ao login; não repita mutações automaticamente.
- **RPC falha:** preserve atomicidade e investigue pelo request ID.
- **Suspeita cross-tenant:** SEV-1; suspenda acessos afetados e audite policies/grants.
- **Migration falha:** pare deploys, não edite migration aplicada e crie correção incremental.
- **Secret exposto:** revogue, rotacione e faça varredura completa.

## Proibido em logs

CPF/CNPJ, dados bancários, documentos, descrições livres, payload financeiro completo, tokens, cookies, senhas, service role e connection strings. Configure redaction antes de habilitar um coletor externo.
