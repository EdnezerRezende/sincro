-- AlterTable
ALTER TABLE "usuarios" ADD COLUMN     "is_admin" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "profissionais" (
    "id" TEXT NOT NULL,
    "nome" TEXT NOT NULL,
    "tags" TEXT[],
    "cidade" TEXT NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "telefone" TEXT NOT NULL,
    "bio" TEXT NOT NULL,
    "ativo" BOOLEAN NOT NULL DEFAULT true,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atualizado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "profissionais_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "profissionais_ativo_idx" ON "profissionais"("ativo");
