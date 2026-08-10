-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS "vector";

-- CreateTable
CREATE TABLE "knowledge_documents" (
    "id" TEXT NOT NULL,
    "titulo" TEXT NOT NULL,
    "arquivo" TEXT NOT NULL,
    "tipo" TEXT NOT NULL,
    "categoria" TEXT NOT NULL,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "knowledge_documents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "knowledge_chunks" (
    "id" TEXT NOT NULL,
    "documento_id" TEXT NOT NULL,
    "conteudo" TEXT NOT NULL,
    "indice_chunk" INTEGER NOT NULL,
    "embedding" vector(1536),
    "metadados" JSONB,
    "criado_em" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "knowledge_chunks_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "knowledge_chunks_documento_id_idx" ON "knowledge_chunks"("documento_id");

-- CreateIndex: HNSW index for fast approximate nearest-neighbor vector search
CREATE INDEX "knowledge_chunks_embedding_hnsw_idx"
    ON "knowledge_chunks" USING hnsw (embedding vector_cosine_ops);

-- CreateIndex: GIN index for full-text search (Portuguese)
CREATE INDEX "knowledge_chunks_fts_idx"
    ON "knowledge_chunks" USING gin (to_tsvector('portuguese', "conteudo"));

-- AddForeignKey
ALTER TABLE "knowledge_chunks"
    ADD CONSTRAINT "knowledge_chunks_documento_id_fkey"
    FOREIGN KEY ("documento_id")
    REFERENCES "knowledge_documents"("id")
    ON DELETE CASCADE
    ON UPDATE CASCADE;
