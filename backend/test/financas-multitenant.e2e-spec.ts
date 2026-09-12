import 'dotenv/config';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { EmailFinanceRegexParserService } from '../src/financas/parser/email-finance-regex-parser.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';

interface ResumoResponseBody {
  saldoLivre: number;
  saldoContas: number;
}

describe('Finanças — isolamento multi-tenant (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let parser: EmailFinanceRegexParserService;
  let userAId: string;
  let userBId: string;

  const firebaseUidA = 'e2e-financas-user-a';
  const firebaseUidB = 'e2e-financas-user-b';
  const authHeaderA = { Authorization: `Bearer test-uid:${firebaseUidA}` };
  const authHeaderB = { Authorization: `Bearer test-uid:${firebaseUidB}` };

  beforeAll(async () => {
    const moduleRef: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(FIREBASE_ADMIN)
      .useValue(buildFakeFirebaseAdmin())
      .compile();

    app = moduleRef.createNestApplication();
    await app.init();
    prisma = moduleRef.get(PrismaService);
    parser = moduleRef.get(EmailFinanceRegexParserService);

    const userA = await prisma.user.upsert({
      where: { firebaseUid: firebaseUidA },
      create: { firebaseUid: firebaseUidA, nome: 'Usuária E2E A' },
      update: {},
    });
    const userB = await prisma.user.upsert({
      where: { firebaseUid: firebaseUidB },
      create: { firebaseUid: firebaseUidB, nome: 'Usuário E2E B' },
      update: {},
    });
    userAId = userA.id;
    userBId = userB.id;
  });

  afterAll(async () => {
    await prisma.lancamentoFinanceiro.deleteMany({
      where: { userId: { in: [userAId, userBId] } },
    });
    await prisma.contaFinanceira.deleteMany({
      where: { userId: { in: [userAId, userBId] } },
    });
    await prisma.user.deleteMany({ where: { id: { in: [userAId, userBId] } } });
    await app.close();
  });

  it("never returns another user's lançamento by id", async () => {
    const lancamento = await prisma.lancamentoFinanceiro.create({
      data: {
        userId: userAId,
        tipo: 'DESPESA',
        descricao: 'Privado de A',
        dataVencimento: new Date(),
        dataCompetencia: new Date(),
        status: 'PENDENTE_REVISAO',
        origem: 'MANUAL',
      },
    });

    await request(app.getHttpServer())
      .patch(`/financas/lancamentos/${lancamento.id}/confirmar`)
      .set(authHeaderB)
      .send({})
      .expect(404);
  });

  it('creates two distinct lançamentos when two users process the same emailMessageId', async () => {
    const emailComum = {
      gmailMessageId: 'msg-encaminhado-1',
      remetente: 'Nubank <fatura@nubank.com.br>',
      assunto: 'Sua fatura fechou',
      recebidoEm: new Date(),
    };

    await parser.processEmail(
      userAId,
      emailComum,
      'Total da fatura: R$ 100,00\nVencimento: 10/10/2026',
    );
    await parser.processEmail(
      userBId,
      emailComum,
      'Total da fatura: R$ 100,00\nVencimento: 10/10/2026',
    );

    const countA = await prisma.lancamentoFinanceiro.count({
      where: { userId: userAId, emailMessageId: 'msg-encaminhado-1' },
    });
    const countB = await prisma.lancamentoFinanceiro.count({
      where: { userId: userBId, emailMessageId: 'msg-encaminhado-1' },
    });
    expect(countA).toBe(1);
    expect(countB).toBe(1);
  });

  it('calculates saldoLivre independently per user', async () => {
    await prisma.contaFinanceira.create({
      data: { userId: userAId, nome: 'Conta A', tipo: 'CORRENTE', saldoAtual: 500 },
    });
    await prisma.contaFinanceira.create({
      data: { userId: userBId, nome: 'Conta B', tipo: 'CORRENTE', saldoAtual: 9999 },
    });

    const resumoA = await request(app.getHttpServer())
      .get('/financas/resumo')
      .set(authHeaderA)
      .expect(200);

    expect((resumoA.body as ResumoResponseBody).saldoContas).toBe(500);
  });
});
