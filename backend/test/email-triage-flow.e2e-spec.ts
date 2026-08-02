import 'dotenv/config';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { GmailOAuthService } from '../src/gmail/gmail-oauth.service';
import { GmailApiClient } from '../src/gmail/gmail-api-client.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { EmailSyncService } from '../src/email-sync/email-sync.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';
import { buildFakeGmailOAuth } from './support/fake-gmail-oauth';
import { buildFakeGmailApiClient } from './support/fake-gmail-api-client';

describe('Email triage flow (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let emailSyncService: EmailSyncService;
  const authHeader = { Authorization: 'Bearer test-uid:triage-user-1' };

  beforeAll(async () => {
    const moduleRef: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(FIREBASE_ADMIN)
      .useValue(buildFakeFirebaseAdmin())
      .overrideProvider(GmailOAuthService)
      .useValue(buildFakeGmailOAuth())
      .overrideProvider(GmailApiClient)
      .useValue(buildFakeGmailApiClient())
      .compile();

    app = moduleRef.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
    await app.init();
    prisma = moduleRef.get(PrismaService);
    emailSyncService = moduleRef.get(EmailSyncService);
  });

  afterAll(async () => {
    await prisma.emailSummary.deleteMany({});
    await prisma.gmailConnection.deleteMany({});
    await prisma.user.deleteMany({ where: { firebaseUid: 'triage-user-1' } });
    await app.close();
  });

  it('connects Gmail, syncs, lists derived summaries without email bodies, and wipes everything on disconnect', async () => {
    await request(app.getHttpServer())
      .post('/users/me')
      .set(authHeader)
      .send({ nome: 'Usuário Triagem' })
      .expect(201);

    await request(app.getHttpServer())
      .post('/gmail/connect')
      .set(authHeader)
      .send({ serverAuthCode: 'test-code' })
      .expect(201);

    const status = await request(app.getHttpServer()).get('/gmail/connection').set(authHeader).expect(200);
    expect(status.body).toEqual({ connected: true, gmailEmail: 'usuario.teste@gmail.com' });

    const user = await prisma.user.findUniqueOrThrow({ where: { firebaseUid: 'triage-user-1' } });
    await emailSyncService.syncUser(user.id);

    const summaries = await request(app.getHttpServer()).get('/resumos-email').set(authHeader).expect(200);
    expect(summaries.body).toHaveLength(2);

    const urgente = summaries.body.find((s: { gmailMessageId: string }) => s.gmailMessageId === 'msg-urgente');
    expect(urgente.categoria).toBe('PRECISA_ATENCAO');
    const newsletter = summaries.body.find((s: { gmailMessageId: string }) => s.gmailMessageId === 'msg-newsletter');
    expect(newsletter.categoria).toBe('PODE_ESPERAR');

    for (const summary of summaries.body) {
      expect(summary).not.toHaveProperty('corpo');
    }

    await request(app.getHttpServer()).delete('/gmail/connection').set(authHeader).expect(200);

    const afterDisconnect = await request(app.getHttpServer()).get('/resumos-email').set(authHeader).expect(200);
    expect(afterDisconnect.body).toEqual([]);
    const connectionAfterDisconnect = await request(app.getHttpServer())
      .get('/gmail/connection')
      .set(authHeader)
      .expect(200);
    expect(connectionAfterDisconnect.body).toEqual({ connected: false, gmailEmail: null });
  });

  it('does not leak email summaries across tenants', async () => {
    const otherAuthHeader = { Authorization: 'Bearer test-uid:triage-user-2' };
    await request(app.getHttpServer()).post('/users/me').set(otherAuthHeader).send({ nome: 'Outro Usuário' }).expect(201);

    const otherSummaries = await request(app.getHttpServer()).get('/resumos-email').set(otherAuthHeader).expect(200);
    expect(otherSummaries.body).toEqual([]);

    await prisma.user.deleteMany({ where: { firebaseUid: 'triage-user-2' } });
  });
});
