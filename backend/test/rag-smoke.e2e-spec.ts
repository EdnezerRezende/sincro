import 'dotenv/config';
import * as fs from 'fs';
import * as path from 'path';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';

/**
 * THROWAWAY manual smoke test — not meant to stay in the repo. Hits the real
 * OpenAI (embeddings) and Anthropic (generation) APIs, so it costs real
 * money and needs real keys in backend/.env. Run once to confirm the RAG
 * pipeline works end to end, read the output, then delete this file.
 */
describe('RAG pipeline (manual smoke test)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  const authHeader = { Authorization: 'Bearer test-uid:rag-smoke-user' };
  let documentoId: string;

  beforeAll(async () => {
    const moduleRef: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(FIREBASE_ADMIN)
      .useValue(buildFakeFirebaseAdmin())
      .compile();

    app = moduleRef.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
    await app.init();
    prisma = moduleRef.get(PrismaService);
  }, 30000);

  afterAll(async () => {
    if (documentoId) {
      await prisma.knowledgeChunk.deleteMany({ where: { documentoId } });
      await prisma.knowledgeDocument.deleteMany({ where: { id: documentoId } });
    }
    await app.close();
  });

  it('uploads a document, embeds it, and answers a question grounded in it', async () => {
    const docxPath = path.join(
      __dirname,
      '../node_modules/mammoth/test/test-data/single-paragraph.docx',
    );
    const docxBuffer = fs.readFileSync(docxPath);

    const uploadRes = await request(app.getHttpServer())
      .post('/rag/documentos')
      .set(authHeader)
      .field('categoria', 'geral')
      .attach('arquivo', docxBuffer, {
        filename: 'smoke-test.docx',
        contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      })
      .expect(201);

    expect(uploadRes.body.documentoId).toEqual(expect.any(String));
    expect(uploadRes.body.totalChunks).toBeGreaterThan(0);
    documentoId = uploadRes.body.documentoId;
    console.log('Upload result:', uploadRes.body);

    const queryRes = await request(app.getHttpServer())
      .post('/rag/consulta')
      .set(authHeader)
      .send({ pergunta: 'O que está andando no ar importado?', categoria: 'geral' })
      .expect(201);

    console.log('Query result:', JSON.stringify(queryRes.body, null, 2));

    expect(queryRes.body.totalFontesUsadas).toBeGreaterThan(0);
    expect(queryRes.body.fontes[0].documentoId).toBe(documentoId);
    expect(queryRes.body.fontes[0].trecho).toContain('Walking on imported air');
    expect(typeof queryRes.body.resposta).toBe('string');
    expect(queryRes.body.resposta.length).toBeGreaterThan(0);
  }, 60000);
});
