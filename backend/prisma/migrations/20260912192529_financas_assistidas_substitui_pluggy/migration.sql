/*
  Warnings:

  - You are about to drop the `boletos_dda` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `conexoes_financeiras` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `contas_financeiras` table. If the table is not empty, all the data it contains will be lost.

*/
-- CreateEnum
CREATE TYPE "TipoContaFinanceira" AS ENUM ('CORRENTE', 'CARTEIRA', 'POUPANCA');

-- CreateEnum
CREATE TYPE "TipoLancamento" AS ENUM ('DESPESA', 'RECEITA', 'FATURA_CARTAO');

-- CreateEnum
CREATE TYPE "StatusLancamento" AS ENUM ('PENDENTE_REVISAO', 'CONFIRMADO', 'IGNORADO');

-- CreateEnum
CREATE TYPE "OrigemLancamento" AS ENUM ('EMAIL_PARSER', 'MANUAL');

-- DropForeignKey
ALTER TABLE "boletos_dda" DROP CONSTRAINT "boletos_dda_user_id_fkey";

-- DropForeignKey
ALTER TABLE "conexoes_financeiras" DROP CONSTRAINT "conexoes_financeiras_user_id_fkey";

-- DropForeignKey
ALTER TABLE "contas_financeiras" DROP CONSTRAINT "contas_financeiras_conexao_id_fkey";

-- DropIndex
DROP INDEX "knowledge_chunks_embedding_hnsw_idx";

-- DropTable
DROP TABLE "boletos_dda";

-- DropTable
DROP TABLE "conexoes_financeiras";

-- DropTable
DROP TABLE "contas_financeiras";

-- CreateTable
CREATE TABLE "contas_financeiras_v2" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "nome" TEXT NOT NULL,
    "tipo" "TipoContaFinanceira" NOT NULL,
    "saldo_atual" DECIMAL(14,2) NOT NULL,
    "cor" TEXT,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "contas_financeiras_v2_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cartoes_credito" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "nome" TEXT NOT NULL,
    "dia_fechamento" INTEGER NOT NULL,
    "dia_vencimento" INTEGER NOT NULL,
    "limite_total" DECIMAL(14,2) NOT NULL,
    "cor" TEXT,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cartoes_credito_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "lancamentos_financeiros" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "tipo" "TipoLancamento" NOT NULL,
    "descricao" TEXT NOT NULL,
    "instituicao" TEXT,
    "valor" DECIMAL(14,2),
    "data_vencimento" DATE NOT NULL,
    "data_competencia" DATE NOT NULL,
    "status" "StatusLancamento" NOT NULL DEFAULT 'PENDENTE_REVISAO',
    "origem" "OrigemLancamento" NOT NULL,
    "is_pago" BOOLEAN NOT NULL DEFAULT false,
    "email_message_id" TEXT,
    "codigo_barras" TEXT,
    "cartao_id" TEXT,
    "conta_id" TEXT,
    "google_event_id" TEXT,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "lancamentos_financeiros_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "contas_financeiras_v2_user_id_idx" ON "contas_financeiras_v2"("user_id");

-- CreateIndex
CREATE INDEX "cartoes_credito_user_id_idx" ON "cartoes_credito"("user_id");

-- CreateIndex
CREATE INDEX "lancamentos_financeiros_user_id_status_idx" ON "lancamentos_financeiros"("user_id", "status");

-- CreateIndex
CREATE INDEX "lancamentos_financeiros_user_id_data_vencimento_idx" ON "lancamentos_financeiros"("user_id", "data_vencimento");

-- CreateIndex
CREATE UNIQUE INDEX "lancamentos_financeiros_user_id_email_message_id_key" ON "lancamentos_financeiros"("user_id", "email_message_id");

-- AddForeignKey
ALTER TABLE "lancamentos_financeiros" ADD CONSTRAINT "lancamentos_financeiros_cartao_id_fkey" FOREIGN KEY ("cartao_id") REFERENCES "cartoes_credito"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "lancamentos_financeiros" ADD CONSTRAINT "lancamentos_financeiros_conta_id_fkey" FOREIGN KEY ("conta_id") REFERENCES "contas_financeiras_v2"("id") ON DELETE SET NULL ON UPDATE CASCADE;
