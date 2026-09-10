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
  const firebaseUid1 = 'triage-user-1';
  const firebaseUid2 = 'triage-user-2';
  const authHeader = { Authorization: `Bearer test-uid:${firebaseUid1}` };
  const otherAuthHeader = { Authorization: `Bearer test-uid:${firebaseUid2}` };

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
    for (const firebaseUid of [firebaseUid1, firebaseUid2]) {
      const user = await prisma.user.findUnique({ where: { firebaseUid } });
      if (user) {
        await prisma.emailSummary.deleteMany({ where: { userId: user.id } });
        await prisma.gmailConnection.deleteMany({ where: { userId: user.id } });
      }
    }
    await prisma.user.deleteMany({ where: { firebaseUid: { in: [firebaseUid1, firebaseUid2] } } });
    await app.close();
  });

  it('connects Gmail, syncs, and lists derived summaries without email bodies', async () => {
    await request(app.getHttpServer())
      .post('/users/me')
      .set(authHeader)
      .send({ nome: 'Usuário Triagem' })
      .expect(201);

    await request(app.getHttpServer())
      .post('/gmail/connect')
      .set(authHeader)
      .send({ serverAuthCode: 'test-code-1' })
      .expect(201);

    const status = await request(app.getHttpServer()).get('/gmail/connection').set(authHeader).expect(200);
    expect(status.body).toEqual({
      connected: true,
      gmailEmail: 'usuario.teste@gmail.com',
      temEscopoEnvio: true,
      temEscopoAgenda: true,
      temEscopoModificacao: false,
    });

    const user1 = await prisma.user.findUniqueOrThrow({ where: { firebaseUid: firebaseUid1 } });
    await emailSyncService.syncUser(user1.id);

    const summaries = await request(app.getHttpServer()).get('/resumos-email').set(authHeader).expect(200);
    expect(summaries.body).toHaveLength(2);

    const urgente = summaries.body.find((s: { gmailMessageId: string }) => s.gmailMessageId === 'msg-urgente');
    expect(urgente.categoria).toBe('PRECISA_ATENCAO');
    const newsletter = summaries.body.find((s: { gmailMessageId: string }) => s.gmailMessageId === 'msg-newsletter');
    expect(newsletter.categoria).toBe('PODE_ESPERAR');

    for (const summary of summaries.body) {
      expect(summary).not.toHaveProperty('corpo');
    }
  });

  it('does not leak email summaries across tenants while both have synced data', async () => {
    // A second tenant connects and syncs independently. Both tenants now have
    // their own 2 rows coexisting in the emailSummary table (4 rows total),
    // which is what makes the per-tenant assertions below falsifiable: if
    // EmailSyncService.list() ever lost its userId scoping, each GET below
    // would return 4 rows instead of 2.
    await request(app.getHttpServer())
      .post('/users/me')
      .set(otherAuthHeader)
      .send({ nome: 'Outro Usuário' })
      .expect(201);
    await request(app.getHttpServer())
      .post('/gmail/connect')
      .set(otherAuthHeader)
      .send({ serverAuthCode: 'test-code-2' })
      .expect(201);

    const user2 = await prisma.user.findUniqueOrThrow({ where: { firebaseUid: firebaseUid2 } });
    await emailSyncService.syncUser(user2.id);

    // Scoped to the two tenants under test: other e2e specs write emailSummary rows of their own,
    // so a global count would assert on an empty database rather than on this test's own data.
    const user1 = await prisma.user.findUniqueOrThrow({ where: { firebaseUid: firebaseUid1 } });
    const totalRowsInDb = await prisma.emailSummary.count({
      where: { userId: { in: [user1.id, user2.id] } },
    });
    expect(totalRowsInDb).toBe(4);

    const tenant1Summaries = await request(app.getHttpServer()).get('/resumos-email').set(authHeader).expect(200);
    const tenant2Summaries = await request(app.getHttpServer()).get('/resumos-email').set(otherAuthHeader).expect(200);

    expect(tenant1Summaries.body).toHaveLength(2);
    expect(tenant2Summaries.body).toHaveLength(2);
  });

  it("disconnecting one tenant's Gmail wipes only that tenant's rows, leaving the other tenant untouched", async () => {
    await request(app.getHttpServer()).delete('/gmail/connection').set(authHeader).expect(200);

    const afterDisconnect = await request(app.getHttpServer()).get('/resumos-email').set(authHeader).expect(200);
    expect(afterDisconnect.body).toEqual([]);
    const connectionAfterDisconnect = await request(app.getHttpServer())
      .get('/gmail/connection')
      .set(authHeader)
      .expect(200);
    expect(connectionAfterDisconnect.body).toEqual({
      connected: false,
      gmailEmail: null,
      temEscopoEnvio: false,
      temEscopoAgenda: false,
      temEscopoModificacao: false,
    });

    // The other tenant's connection and summaries must survive tenant 1's disconnect.
    const tenant2Summaries = await request(app.getHttpServer()).get('/resumos-email').set(otherAuthHeader).expect(200);
    expect(tenant2Summaries.body).toHaveLength(2);
    const tenant2Connection = await request(app.getHttpServer())
      .get('/gmail/connection')
      .set(otherAuthHeader)
      .expect(200);
    expect(tenant2Connection.body).toEqual({
      connected: true,
      gmailEmail: 'usuario.teste@gmail.com',
      temEscopoEnvio: true,
      temEscopoAgenda: true,
      temEscopoModificacao: false,
    });
  });

  describe('archive/delete (gmail.modify scope)', () => {
    const firebaseUid3 = 'triage-user-3';
    const firebaseUid4 = 'triage-user-4';
    const authHeader3 = { Authorization: `Bearer test-uid:${firebaseUid3}` };
    const authHeader4 = { Authorization: `Bearer test-uid:${firebaseUid4}` };
    const FULL_SCOPE_WITH_MODIFY =
      'https://www.googleapis.com/auth/gmail.readonly ' +
      'https://www.googleapis.com/auth/gmail.send ' +
      'https://www.googleapis.com/auth/gmail.modify ' +
      'https://www.googleapis.com/auth/calendar.events';

    let appWithModify: INestApplication<App>;
    let appWithoutModify: INestApplication<App>;

    afterAll(async () => {
      for (const firebaseUid of [firebaseUid3, firebaseUid4]) {
        const user = await prisma.user.findUnique({ where: { firebaseUid } });
        if (user) {
          await prisma.emailSummary.deleteMany({ where: { userId: user.id } });
          await prisma.gmailConnection.deleteMany({ where: { userId: user.id } });
        }
      }
      await prisma.user.deleteMany({ where: { firebaseUid: { in: [firebaseUid3, firebaseUid4] } } });
      await appWithModify.close();
      await appWithoutModify.close();
    });

    it('archives an e-mail: returns 200 and the row disappears from GET /resumos-email', async () => {
      const moduleWithModify: TestingModule = await Test.createTestingModule({
        imports: [AppModule],
      })
        .overrideProvider(FIREBASE_ADMIN)
        .useValue(buildFakeFirebaseAdmin())
        .overrideProvider(GmailOAuthService)
        .useValue(buildFakeGmailOAuth({ scope: FULL_SCOPE_WITH_MODIFY }))
        .overrideProvider(GmailApiClient)
        .useValue(buildFakeGmailApiClient())
        .compile();
      appWithModify = moduleWithModify.createNestApplication();
      appWithModify.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
      await appWithModify.init();

      await request(appWithModify.getHttpServer())
        .post('/users/me')
        .set(authHeader3)
        .send({ nome: 'Usuário Arquivar' })
        .expect(201);
      await request(appWithModify.getHttpServer())
        .post('/gmail/connect')
        .set(authHeader3)
        .send({ serverAuthCode: 'test-code-3' })
        .expect(201);

      const user3 = await prisma.user.findUniqueOrThrow({ where: { firebaseUid: firebaseUid3 } });
      const emailSyncService3 = moduleWithModify.get(EmailSyncService);
      await emailSyncService3.syncUser(user3.id);

      const summaries = await request(appWithModify.getHttpServer())
        .get('/resumos-email')
        .set(authHeader3)
        .expect(200);
      expect(summaries.body).toHaveLength(2);
      const emailIdToArchive = summaries.body[0].id as string;

      const archiveResult = await request(appWithModify.getHttpServer())
        .post(`/resumos-email/${emailIdToArchive}/arquivar`)
        .set(authHeader3)
        .expect(201);
      expect(archiveResult.body).toEqual({ arquivado: true });

      const afterArchive = await request(appWithModify.getHttpServer())
        .get('/resumos-email')
        .set(authHeader3)
        .expect(200);
      expect(afterArchive.body).toHaveLength(1);
      expect(afterArchive.body.find((s: { id: string }) => s.id === emailIdToArchive)).toBeUndefined();

      const emailIdToDelete = afterArchive.body[0].id as string;
      const deleteResult = await request(appWithModify.getHttpServer())
        .post(`/resumos-email/${emailIdToDelete}/excluir`)
        .set(authHeader3)
        .expect(201);
      expect(deleteResult.body).toEqual({ excluido: true });

      const afterDelete = await request(appWithModify.getHttpServer())
        .get('/resumos-email')
        .set(authHeader3)
        .expect(200);
      expect(afterDelete.body).toEqual([]);
    });

    it('rejects archive/excluir with 403 when the tenant never granted the gmail.modify scope', async () => {
      const moduleWithoutModify: TestingModule = await Test.createTestingModule({
        imports: [AppModule],
      })
        .overrideProvider(FIREBASE_ADMIN)
        .useValue(buildFakeFirebaseAdmin())
        .overrideProvider(GmailOAuthService)
        .useValue(buildFakeGmailOAuth()) // default scope has no gmail.modify
        .overrideProvider(GmailApiClient)
        .useValue(buildFakeGmailApiClient())
        .compile();
      appWithoutModify = moduleWithoutModify.createNestApplication();
      appWithoutModify.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
      await appWithoutModify.init();

      await request(appWithoutModify.getHttpServer())
        .post('/users/me')
        .set(authHeader4)
        .send({ nome: 'Usuário Sem Escopo' })
        .expect(201);
      await request(appWithoutModify.getHttpServer())
        .post('/gmail/connect')
        .set(authHeader4)
        .send({ serverAuthCode: 'test-code-4' })
        .expect(201);

      const user4 = await prisma.user.findUniqueOrThrow({ where: { firebaseUid: firebaseUid4 } });
      const emailSyncService4 = moduleWithoutModify.get(EmailSyncService);
      await emailSyncService4.syncUser(user4.id);

      const summaries = await request(appWithoutModify.getHttpServer())
        .get('/resumos-email')
        .set(authHeader4)
        .expect(200);
      const emailId = summaries.body[0].id as string;

      await request(appWithoutModify.getHttpServer())
        .post(`/resumos-email/${emailId}/arquivar`)
        .set(authHeader4)
        .expect(403);
      await request(appWithoutModify.getHttpServer())
        .post(`/resumos-email/${emailId}/excluir`)
        .set(authHeader4)
        .expect(403);

      // The rows must stay untouched — a 403 must never look like a silent success.
      const stillThere = await request(appWithoutModify.getHttpServer())
        .get('/resumos-email')
        .set(authHeader4)
        .expect(200);
      expect(stillThere.body).toHaveLength(2);
    });
  });
});
