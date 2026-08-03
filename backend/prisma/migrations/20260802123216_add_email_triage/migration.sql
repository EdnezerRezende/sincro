-- AlterTable
ALTER TABLE "usuarios" ADD COLUMN     "fcm_token" TEXT,
ADD COLUMN     "plano" TEXT NOT NULL DEFAULT 'simples';

-- CreateTable
CREATE TABLE "conexoes_gmail" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "refresh_token_criptografado" TEXT NOT NULL,
    "gmail_email" TEXT NOT NULL,
    "last_history_id" TEXT,
    "ultima_sincronizacao" TIMESTAMP(3),
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "conexoes_gmail_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "resumos_email" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "gmail_message_id" TEXT NOT NULL,
    "remetente" TEXT NOT NULL,
    "assunto" TEXT NOT NULL,
    "resumo_curto" TEXT NOT NULL,
    "categoria" TEXT NOT NULL,
    "recebido_em" TIMESTAMP(3) NOT NULL,
    "lido_no_app" BOOLEAN NOT NULL DEFAULT false,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "resumos_email_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "conexoes_gmail_user_id_key" ON "conexoes_gmail"("user_id");

-- CreateIndex
CREATE INDEX "resumos_email_user_id_idx" ON "resumos_email"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "resumos_email_user_id_gmail_message_id_key" ON "resumos_email"("user_id", "gmail_message_id");

-- AddForeignKey
ALTER TABLE "conexoes_gmail" ADD CONSTRAINT "conexoes_gmail_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "resumos_email" ADD CONSTRAINT "resumos_email_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "usuarios"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
