# Plano de Contas FINAGRO — importação pendente

O repositório ainda não contém uma relação integral, versionada e homologada das
contas do Plano FINAGRO original. Por isso, a migration de configuração cria a
infraestrutura de templates e sua aplicação idempotente, mas não inventa nem
semeia contas.

Para liberar o template inicial será necessário fornecer um dataset oficial com,
no mínimo: código, nome, vínculo pai, ordem, tipo gerencial, natureza e os flags
de participação/requisitos já existentes no schema. O dataset deve preservar o
mapeamento legado Grupo → Subgrupo sem transformar esses nomes em regras fixas.
