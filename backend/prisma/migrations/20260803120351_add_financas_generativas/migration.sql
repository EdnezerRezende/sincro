-- AlterTable
ALTER TABLE "usuarios" ADD COLUMN     "dia_recebimento" INTEGER;

-- CreateTable
CREATE TABLE "conexoes_financeiras" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "pluggy_item_id" TEXT NOT NULL,
    "instituicao" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "conexoes_financeiras_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "contas_financeiras" (
    "id" TEXT NOT NULL,
    "conexao_id" TEXT NOT NULL,
    "pluggy_account_id" TEXT NOT NULL,
    "tipo" TEXT NOT NULL,
    "nome" TEXT NOT NULL,
    "saldo_ou_fatura" DECIMAL(14,2) NOT NULL,
    "vencimento_fatura" DATE,
    "notificado_em" TIMESTAMP(3),
    "atualizado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "contas_financeiras_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "boletos_dda" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "codigo_barras" TEXT NOT NULL,
    "valor" DECIMAL(14,2) NOT NULL,
    "vencimento" DATE NOT NULL,
    "pago" BOOLEAN NOT NULL DEFAULT false,
    "notificado_em" TIMESTAMP(3),
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "boletos_dda_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "conexoes_financeiras_user_id_idx" ON "conexoes_financeiras"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "conexoes_financeiras_user_id_pluggy_item_id_key" ON "conexoes_financeiras"("user_id", "pluggy_item_id");

-- CreateIndex
CREATE INDEX "contas_financeiras_conexao_id_idx" ON "contas_financeiras"("conexao_id");

-- CreateIndex
CREATE UNIQUE INDEX "contas_financeiras_conexao_id_pluggy_account_id_key" ON "contas_financeiras"("conexao_id", "pluggy_account_id");

-- CreateIndex
CREATE INDEX "boletos_dda_user_id_idx" ON "boletos_dda"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "boletos_dda_user_id_codigo_barras_key" ON "boletos_dda"("user_id", "codigo_barras");

-- AddForeignKey
ALTER TABLE "conexoes_financeiras" ADD CONSTRAINT "conexoes_financeiras_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "contas_financeiras" ADD CONSTRAINT "contas_financeiras_conexao_id_fkey" FOREIGN KEY ("conexao_id") REFERENCES "conexoes_financeiras"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "boletos_dda" ADD CONSTRAINT "boletos_dda_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
