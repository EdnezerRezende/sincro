import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { KnowledgeBaseService, CategoriaRag } from './knowledge-base.service';
import { RagService } from './rag.service';
import { UploadDocumentDto } from './dto/upload-document.dto';
import { QueryRagDto } from './dto/query-rag.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('rag')
export class RagController {
  constructor(
    private readonly knowledgeBase: KnowledgeBaseService,
    private readonly rag: RagService,
  ) {}

  @Post('documentos')
  @UseInterceptors(
    FileInterceptor('arquivo', {
      limits: { fileSize: 20 * 1024 * 1024 },
      fileFilter: (_req, file, cb) => {
        const allowed = [
          'application/pdf',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'application/msword',
        ];
        if (allowed.includes(file.mimetype)) {
          cb(null, true);
        } else {
          cb(new Error('Apenas arquivos PDF e DOCX são aceitos'), false);
        }
      },
    }),
  )
  async uploadDocument(
    @UploadedFile() file: Express.Multer.File,
    @Body() dto: UploadDocumentDto,
  ) {
    const categoria: CategoriaRag = dto.categoria ?? 'geral';
    return this.knowledgeBase.addDocument(
      file.buffer,
      file.originalname,
      file.mimetype,
      categoria,
    );
  }

  @Get('documentos')
  async listDocuments() {
    return this.knowledgeBase.listDocuments();
  }

  @Delete('documentos/:id')
  async deleteDocument(@Param('id') id: string) {
    await this.knowledgeBase.deleteDocument(id);
    return { sucesso: true };
  }

  @Post('consulta')
  async query(@Body() dto: QueryRagDto) {
    return this.rag.query(dto.pergunta, dto.categoria, dto.topK);
  }
}
