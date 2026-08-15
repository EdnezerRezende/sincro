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
    });
  });
});
