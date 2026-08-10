import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaModule } from '../prisma/prisma.module';
import { EmbeddingService } from './embedding.service';
import { DocumentProcessorService } from './document-processor.service';
import { KnowledgeBaseService } from './knowledge-base.service';
import { HybridSearchService } from './hybrid-search.service';
import { RagService } from './rag.service';
import { RagController } from './rag.controller';

@Module({
  imports: [PrismaModule, AuthModule],
  providers: [
    EmbeddingService,
    DocumentProcessorService,
    KnowledgeBaseService,
    HybridSearchService,
    RagService,
  ],
  controllers: [RagController],
  exports: [RagService, KnowledgeBaseService],
})
export class RagModule {}
