-- AlterEnum: Adicionar WHATSAPP à OrigemLancamento
ALTER TYPE "OrigemLancamento" ADD VALUE 'WHATSAPP';

-- AlterTable LancamentoFinanceiro: Adicionar whatsapp_message_id
ALTER TABLE "lancamentos_financeiros" ADD COLUMN "whatsapp_message_id" TEXT;
CREATE UNIQUE INDEX "lancamentos_financeiros_user_id_whatsapp_message_id_key" ON "lancamentos_financeiros"("user_id", "whatsapp_message_id");

-- AlterTable User: Adicionar app_build (§6.7 compatibilidade)
ALTER TABLE "usuarios" ADD COLUMN "app_build" INTEGER;

-- CreateTable WhatsappVinculo
CREATE TABLE "whatsapp_vinculos" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "telefone_hash" TEXT,
    "telefone_criptografado" TEXT,
    "codigo_hash" TEXT,
    "codigo_expira_em" TIMESTAMP(3),
    "aviso_indisponivel_em" TIMESTAMP(3),
    "aviso_atualizar_em" TIMESTAMP(3),
    "verificado_em" TIMESTAMP(3),
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "whatsapp_vinculos_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "whatsapp_vinculos_user_id_key" ON "whatsapp_vinculos"("user_id");
CREATE UNIQUE INDEX "whatsapp_vinculos_telefone_hash_key" ON "whatsapp_vinculos"("telefone_hash");
CREATE UNIQUE INDEX "whatsapp_vinculos_codigo_hash_key" ON "whatsapp_vinculos"("codigo_hash");

-- CreateTable WhatsappRemetente
CREATE TABLE "whatsapp_remetentes" (
    "telefone_hash" TEXT NOT NULL,
    "falhas" INTEGER NOT NULL DEFAULT 0,
    "bloqueado_ate" TIMESTAMP(3),
    "aviso_nao_vinculado_em" TIMESTAMP(3),
    "ultima_mensagem_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "whatsapp_remetentes_pkey" PRIMARY KEY ("telefone_hash")
);
CREATE INDEX "whatsapp_remetentes_ultima_mensagem_em_idx" ON "whatsapp_remetentes"("ultima_mensagem_em");

-- CreateTable WhatsappMensagem
CREATE TABLE "whatsapp_mensagens" (
    "id" TEXT NOT NULL,
    "wamid" TEXT NOT NULL,
    "telefone_hash" TEXT,
    "user_id" TEXT,
    "direcao" TEXT NOT NULL,
    "tipo" TEXT NOT NULL,
    "texto_cifrado" TEXT,
    "lancamento_id" TEXT,
    "efeito" TEXT,
    "google_event_id_remover" TEXT,
    "resposta_wamid" TEXT,
    "resposta_payload_cifrado" TEXT,
    "desfecho_rascunho" TEXT,
    "status" TEXT NOT NULL,
    "tentativas" INTEGER NOT NULL DEFAULT 0,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "whatsapp_mensagens_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "whatsapp_mensagens_wamid_key" ON "whatsapp_mensagens"("wamid");
CREATE INDEX "whatsapp_mensagens_user_id_criado_em_idx" ON "whatsapp_mensagens"("user_id", "criado_em");
CREATE INDEX "whatsapp_mensagens_status_criado_em_idx" ON "whatsapp_mensagens"("status", "criado_em");

-- CreateTable WhatsappConversaEstado
CREATE TABLE "whatsapp_conversa_estado" (
    "user_id" TEXT NOT NULL,
    "etapa" TEXT NOT NULL,
    "rascunho" JSONB NOT NULL,
    "expira_em" TIMESTAMP(3) NOT NULL,
    "versao" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "whatsapp_conversa_estado_pkey" PRIMARY KEY ("user_id")
);
CREATE INDEX "whatsapp_conversa_estado_expira_em_idx" ON "whatsapp_conversa_estado"("expira_em");
