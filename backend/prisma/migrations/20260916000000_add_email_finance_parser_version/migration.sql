-- AlterTable
ALTER TABLE "resumos_email" ADD COLUMN     "label_ids" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "parser_financas_versao" INTEGER,
ADD COLUMN     "parser_financas_tentativas" INTEGER NOT NULL DEFAULT 0;

-- CreateIndex
CREATE INDEX "resumos_email_user_id_parser_financas_versao_parser_financas_tentativas_idx" ON "resumos_email"("user_id", "parser_financas_versao", "parser_financas_tentativas");
