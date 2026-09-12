-- Recria o índice HNSW de knowledge_chunks.embedding, removido
-- involuntariamente pela migration 20260912192529_financas_assistidas_substitui_pluggy
-- (o Prisma não reconhece índices HNSW e propôs DROP INDEX para ele durante
-- `prisma migrate dev` — ver comentário no model KnowledgeChunk em schema.prisma).
-- Mesma definição usada originalmente na migration 20260803210000_add_rag_knowledge_base.
CREATE INDEX IF NOT EXISTS "knowledge_chunks_embedding_hnsw_idx"
    ON "knowledge_chunks" USING hnsw (embedding vector_cosine_ops);
