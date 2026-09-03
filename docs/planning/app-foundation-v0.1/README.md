# FINAGRO App Foundation v0.1

Pacote de especificação para a etapa imediatamente posterior à validação das migrations PostgreSQL/Supabase.

Arquivos:
- `AGENTS.md`: regras permanentes para Codex/agentes de desenvolvimento.
- `docs/APP_ARCHITECTURE.md`: arquitetura da aplicação e limites da etapa.
- `CODEX_PROMPT_ETAPA_FUNDACAO_APP.md`: prompt pronto para executar no Codex após o banco estar validado.

A ordem correta é:
1. validar `FINAGRO_DB_Foundation_v0.2` em Supabase local;
2. garantir testes P0 verdes;
3. colocar `AGENTS.md` na raiz do repositório;
4. executar o prompt de fundação da aplicação no Codex;
5. revisar antes de começar Plano de Contas e Rateios.
