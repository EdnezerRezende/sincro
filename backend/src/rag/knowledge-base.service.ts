import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { DocumentProcessorService } from './document-processor.service';
import { EmbeddingService } from './embedding.service';

export type CategoriaRag = 'tea' | 'financas' | 'geral';

export interface DocumentoListItem {
  id: string;
  titulo: string;
  arquivo: string;
  tipo: string;
  categoria: string;
  totalChunks: number;
  criadoEm: Date;
}

@Injectable()
export class KnowledgeBaseService {
  private readonly logger = new Logger(KnowledgeBaseService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly processor: DocumentProcessorService,
    private readonly embeddings: EmbeddingService,
  ) {}

  async addDocument(
    buffer: Buffer,
    originalname: string,
    mimeType: string,
    categoria: CategoriaRag,
  ): Promise<{ documentoId: string; totalChunks: number }> {
    this.logger.log(`Processando documento: ${originalname}`);

    const textoExtraido = await this.processor.extractText(buffer, mimeType);
    const chunks = this.processor.chunkText(textoExtraido, originalname);

    if (chunks.length === 0) {
      throw new Error('Nenhum conteúdo de texto encontrado no documento.');
    }

    const tipo = mimeType.includes('pdf') ? 'pdf' : 'docx';

    const documento = await this.prisma.knowledgeDocument.create({
      data: {
        titulo: originalname.replace(/\.[^/.]+$/, ''),
        arquivo: originalname,
        tipo,
        categoria,
      },
    });

    this.logger.log(`Gerando ${chunks.length} embeddings para "${originalname}"...`);

    const BATCH_SIZE = 20;
    for (let i = 0; i < chunks.length; i += BATCH_SIZE) {
      const batch = chunks.slice(i, i + BATCH_SIZE);
      const embeddingVectors = await this.embeddings.generateEmbeddings(
        batch.map((c) => c.content),
      );

      for (let j = 0; j < batch.length; j++) {
        const chunk = batch[j];
        const embeddingStr = this.embeddings.formatEmbeddingForPg(embeddingVectors[j]);

        await this.prisma.$executeRaw`
          INSERT INTO knowledge_chunks (id, documento_id, conteudo, indice_chunk, embedding, metadados, criado_em)
          VALUES (
            gen_random_uuid(),
            ${documento.id},
            ${chunk.content},
            ${chunk.index},
            ${embeddingStr}::vector,
            ${JSON.stringify(chunk.metadata)}::jsonb,
            NOW()
          )
        `;
      }

      this.logger.log(`Batch ${Math.floor(i / BATCH_SIZE) + 1}/${Math.ceil(chunks.length / BATCH_SIZE)} processado`);
    }

    this.logger.log(`Documento "${originalname}" indexado com sucesso (${chunks.length} chunks)`);
    return { documentoId: documento.id, totalChunks: chunks.length };
  }

  async listDocuments(): Promise<DocumentoListItem[]> {
    const docs = await this.prisma.knowledgeDocument.findMany({
      orderBy: { criadoEm: 'desc' },
      include: { _count: { select: { chunks: true } } },
    });

    return docs.map((d) => ({
      id: d.id,
      titulo: d.titulo,
      arquivo: d.arquivo,
      tipo: d.tipo,
      categoria: d.categoria,
      totalChunks: d._count.chunks,
      criadoEm: d.criadoEm,
    }));
  }

  async deleteDocument(id: string): Promise<void> {
    const doc = await this.prisma.knowledgeDocument.findUnique({ where: { id } });
    if (!doc) throw new NotFoundException(`Documento ${id} não encontrado`);
    await this.prisma.knowledgeDocument.delete({ where: { id } });
    this.logger.log(`Documento ${id} removido`);
  }
}
