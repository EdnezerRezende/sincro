-- Suporta a paginação por cursor de EmailSyncService.listarPagina (recebidoEm desc, id desc como
-- desempate) sem sort em memória em páginas fundas. Nomes confirmados com
-- `npx prisma migrate diff --from-schema <schema HEAD> --to-schema prisma/schema.prisma --script`.
-- `resumos_email_user_id_idx` (@@index([userId]) solto) é removido por ser prefixo estrito deste
-- índice novo: qualquer query que hoje filtra só por userId continua igualmente servida por ele,
-- então mantê-lo só custava escrita sem ganho de leitura (ver EmailSyncService e
-- GmailConnectionsService — nenhuma query de resumos_email depende de um índice de userId isolado).
-- DropIndex
DROP INDEX "resumos_email_user_id_idx";

-- CreateIndex
CREATE INDEX "resumos_email_user_id_recebido_em_id_idx" ON "resumos_email"("user_id", "recebido_em" DESC, "id" DESC);
