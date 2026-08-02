-- CreateTable
CREATE TABLE "usuarios" (
    "id" TEXT NOT NULL,
    "firebase_uid" TEXT NOT NULL,
    "nome" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "usuarios_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "perfis_sensoriais" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "dados" JSONB NOT NULL,
    "versao" INTEGER NOT NULL DEFAULT 1,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "perfis_sensoriais_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "contatos_confianca" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "nome" TEXT NOT NULL,
    "relacao" TEXT NOT NULL,
    "whatsapp" TEXT NOT NULL,
    "prioridade" INTEGER NOT NULL DEFAULT 0,
    "consentimento_aceito_em" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "contatos_confianca_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "usuarios_firebase_uid_key" ON "usuarios"("firebase_uid");

-- CreateIndex
CREATE UNIQUE INDEX "perfis_sensoriais_user_id_key" ON "perfis_sensoriais"("user_id");

-- AddForeignKey
ALTER TABLE "perfis_sensoriais" ADD CONSTRAINT "perfis_sensoriais_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "contatos_confianca" ADD CONSTRAINT "contatos_confianca_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
