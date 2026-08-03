import 'dotenv/config';
import { createHmac } from 'crypto';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { PluggyApiClient } from '../src/pluggy/pluggy-api-client.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';
import { buildFakePluggyApiClient } from './support/fake-pluggy-api-client';

describe('Finance flow (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  const firebaseUid1 = 'finance-user-1';
  const firebaseUid2 = 'finance-user-2';
  const authHeader = { Authorization: `Bearer test-uid:${firebaseUid1}` };
  const otherAuthHeader = { Authorization: `Bearer test-uid:${firebaseUid2}` };

  beforeAll(async () => {
    process.env.PLUGGY_WEBHOOK_SECRET = 'test-webhook-secret';

    const moduleRef: TestingModule = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(FIREBASE_ADMIN)
      .useValue(buildFakeFirebaseAdmin())
      .overrideProvider(PluggyApiClient)
      .useValue(buildFakePluggyApiClient())
      .compile();

    app = moduleRef.createNestApplication({ rawBody: true });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
    await app.init();
    prisma = moduleRef.get(PrismaService);
  });

  afterAll(async () => {
    for (const firebaseUid of [firebaseUid1, firebaseUid2]) {
      const user = await prisma.user.findUnique({ where: { firebaseUid } });
      if (user) {
        await prisma.financeAccount.deleteMany({ where: { conexao: { userId: user.id } } });
        await prisma.financeConnection.deleteMany({ where: { userId: user.id } });
        await prisma.boletoDda.deleteMany({ where: { userId: user.id } });
      }
    }
    await prisma.user.deleteMany({ where: { firebaseUid: { in: [firebaseUid1, firebaseUid2] } } });
    await app.close();
  });

  it('connects an institution, syncs via webhook, and computes saldo livre', async () => {
    await request(app.getHttpServer()).post('/users/me').set(authHeader).send({ nome: 'Usuário Finanças' }).expect(201);

    await request(app.getHttpServer())
      .post('/financas/conexoes')
      .set(authHeader)
      .send({ itemId: 'item-tenant-1' })
      .expect(201);

    const payload = { event: 'item/updated', itemId: 'item-tenant-1' };
    const rawBody = JSON.stringify(payload);
    const signature = createHmac('sha256', 'test-webhook-secret').update(rawBody).digest('hex');
    await request(app.getHttpServer())
      .post('/financas/webhooks/pluggy')
      .set('x-pluggy-signature', signature)
      .set('Content-Type', 'application/json')
      .send(rawBody)
      .expect(201);

    const resumo = await request(app.getHttpServer()).get('/financas/resumo').set(authHeader).expect(200);
    // saldo livre = 2000 (conta) - 500 (fatura aberta) - 100 (boleto dentro do ciclo, sem dia_recebimento = fim do mês) = 1400
    expect(resumo.body.saldoLivre).toBe(1400);
    expect(resumo.body.contas).toHaveLength(2);
    expect(resumo.body.boletos).toHaveLength(1);
  });

  it('does not leak finance data across tenants', async () => {
    await request(app.getHttpServer())
      .post('/users/me')
      .set(otherAuthHeader)
      .send({ nome: 'Outro Usuário' })
      .expect(201);
    await request(app.getHttpServer())
      .post('/financas/conexoes')
      .set(otherAuthHeader)
      .send({ itemId: 'item-tenant-2' })
      .expect(201);
    await request(app.getHttpServer()).post('/financas/sync').set(otherAuthHeader).expect(201);

    const tenant1Resumo = await request(app.getHttpServer()).get('/financas/resumo').set(authHeader).expect(200);
    const tenant2Resumo = await request(app.getHttpServer()).get('/financas/resumo').set(otherAuthHeader).expect(200);

    expect(tenant1Resumo.body.contas).toHaveLength(2);
    expect(tenant2Resumo.body.contas).toHaveLength(1);
    expect(tenant2Resumo.body.boletos).toHaveLength(0);
  });

  it("rejects deleting another tenant's connection with 404 and leaves that tenant's data intact", async () => {
    const tenant2Conexoes = await request(app.getHttpServer()).get('/financas/conexoes').set(otherAuthHeader).expect(200);
    const tenant2ConnectionId = tenant2Conexoes.body[0].id;

    await request(app.getHttpServer())
      .delete(`/financas/conexoes/${tenant2ConnectionId}`)
      .set(authHeader)
      .expect(404);

    const tenant2Resumo = await request(app.getHttpServer()).get('/financas/resumo').set(otherAuthHeader).expect(200);
    expect(tenant2Resumo.body.contas).toHaveLength(1);

    // E o inverso: o tenant 2 também não consegue apagar a conexão do tenant 1.
    const tenant1Conexoes = await request(app.getHttpServer()).get('/financas/conexoes').set(authHeader).expect(200);
    await request(app.getHttpServer())
      .delete(`/financas/conexoes/${tenant1Conexoes.body[0].id}`)
      .set(otherAuthHeader)
      .expect(404);

    const tenant1Resumo = await request(app.getHttpServer()).get('/financas/resumo').set(authHeader).expect(200);
    expect(tenant1Resumo.body.contas).toHaveLength(2);
  });

  it("disconnecting one tenant's connection wipes only that tenant's data", async () => {
    const conexoes = await request(app.getHttpServer()).get('/financas/conexoes').set(authHeader).expect(200);
    const connectionId = conexoes.body[0].id;

    await request(app.getHttpServer()).delete(`/financas/conexoes/${connectionId}`).set(authHeader).expect(200);

    const resumoAfter = await request(app.getHttpServer()).get('/financas/resumo').set(authHeader).expect(200);
    expect(resumoAfter.body.contas).toHaveLength(0);
    expect(resumoAfter.body.boletos).toHaveLength(0);

    const tenant2Resumo = await request(app.getHttpServer()).get('/financas/resumo').set(otherAuthHeader).expect(200);
    expect(tenant2Resumo.body.contas).toHaveLength(1);
  });
});
