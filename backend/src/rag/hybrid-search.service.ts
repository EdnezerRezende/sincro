import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { EmbeddingService } from './embedding.service';

export interface ChunkResult {
  id: string;
  documentoId: string;
  conteudo: string;
  indiceChunk: number;
  metadados: Record<string, unknown> | null;
  score: number;
}

interface RawChunkRow {
  id: string;
  documento_id: string;
  conteudo: string;
  indice_chunk: number;
  metadados: Record<string, unknown> | null;
}

const RRF_K = 60;

@Injectable()
export class HybridSearchService {
  private readonly logger = new Logger(HybridSearchService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly embeddingService: EmbeddingService,
  ) {}

  async search(
    query: string,
    topK = 8,
    categoria?: string,
  ): Promise<ChunkResult[]> {
    const queryEmbedding = await this.embeddingService.generateEmbedding(query);
    const embeddingStr = this.embeddingService.formatEmbeddingForPg(queryEmbedding);

    const [vectorResults, bm25Results] = await Promise.all([
      this.vectorSearch(embeddingStr, topK * 2, categoria),
      this.fullTextSearch(query, topK * 2, categoria),
    ]);

    return this.rrfFusion(vectorResults, bm25Results, topK);
  }

  private async vectorSearch(
    embeddingStr: string,
    limit: number,
    categoria?: string,
  ): Promise<RawChunkRow[]> {
    const categoryFilter = categoria
      ? `AND kd.categoria = '${categoria}'`
      : '';

    const rows = await this.prisma.$queryRawUnsafe<RawChunkRow[]>(`
      SELECT kc.id, kc.documento_id, kc.conteudo, kc.indice_chunk, kc.metadados
      FROM knowledge_chunks kc
      INNER JOIN knowledge_documents kd ON kd.id = kc.documento_id
      WHERE kc.embedding IS NOT NULL
        ${categoryFilter}
      ORDER BY kc.embedding <=> '${embeddingStr}'::vector
      LIMIT ${limit}
    `);

    return rows;
  }

  private async fullTextSearch(
    query: string,
    limit: number,
    categoria?: string,
  ): Promise<RawChunkRow[]> {
    const sanitized = query.replace(/'/g, "''");
    const categoryFilter = categoria
      ? `AND kd.categoria = '${categoria}'`
      : '';

    const rows = await this.prisma.$queryRawUnsafe<RawChunkRow[]>(`
      SELECT kc.id, kc.documento_id, kc.conteudo, kc.indice_chunk, kc.metadados
      FROM knowledge_chunks kc
      INNER JOIN knowledge_documents kd ON kd.id = kc.documento_id
      WHERE to_tsvector('portuguese', kc.conteudo) @@ plainto_tsquery('portuguese', '${sanitized}')
        ${categoryFilter}
      ORDER BY ts_rank(to_tsvector('portuguese', kc.conteudo), plainto_tsquery('portuguese', '${sanitized}')) DESC
      LIMIT ${limit}
    `);

    return rows;
  }

  private rrfFusion(
    vectorResults: RawChunkRow[],
    bm25Results: RawChunkRow[],
    topK: number,
  ): ChunkResult[] {
    const scores = new Map<string, { row: RawChunkRow; score: number }>();

    vectorResults.forEach((row, rank) => {
      const rrfScore = 1 / (RRF_K + rank + 1);
      const existing = scores.get(row.id);
      scores.set(row.id, {
        row,
        score: (existing?.score ?? 0) + rrfScore,
      });
    });

    bm25Results.forEach((row, rank) => {
      const rrfScore = 1 / (RRF_K + rank + 1);
      const existing = scores.get(row.id);
      scores.set(row.id, {
        row: existing?.row ?? row,
        score: (existing?.score ?? 0) + rrfScore,
      });
    });

    const sorted = Array.from(scores.values())
      .sort((a, b) => b.score - a.score)
      .slice(0, topK);

    this.logger.debug(
      `Hybrid search: ${vectorResults.length} vetorial + ${bm25Results.length} BM25 → ${sorted.length} fusionados`,
    );

    return sorted.map(({ row, score }) => ({
      id: row.id,
      documentoId: row.documento_id,
      conteudo: row.conteudo,
      indiceChunk: row.indice_chunk,
      metadados: row.metadados,
      score,
    }));
  }
}
