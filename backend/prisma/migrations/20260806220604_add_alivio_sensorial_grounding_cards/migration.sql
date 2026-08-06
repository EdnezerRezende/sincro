-- CreateTable
CREATE TABLE "cartoes_aterramento" (
    "id" TEXT NOT NULL,
    "titulo" TEXT NOT NULL,
    "categoria" TEXT NOT NULL,
    "conteudo" TEXT NOT NULL,
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cartoes_aterramento_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cartoes_favoritos" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "card_id" TEXT NOT NULL,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cartoes_favoritos_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "cartoes_aterramento_ativo_idx" ON "cartoes_aterramento"("ativo");

-- CreateIndex
CREATE INDEX "cartoes_favoritos_user_id_idx" ON "cartoes_favoritos"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "cartoes_favoritos_user_id_card_id_key" ON "cartoes_favoritos"("user_id", "card_id");

-- AddForeignKey
ALTER TABLE "cartoes_favoritos" ADD CONSTRAINT "cartoes_favoritos_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cartoes_favoritos" ADD CONSTRAINT "cartoes_favoritos_card_id_fkey" FOREIGN KEY ("card_id") REFERENCES "cartoes_aterramento"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
