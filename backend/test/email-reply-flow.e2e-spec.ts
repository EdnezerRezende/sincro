// backend/test/email-reply-flow.e2e-spec.ts
import 'dotenv/config';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { GmailOAuthService } from '../src/gmail/gmail-oauth.service';
import { GmailApiClient } from '../src/gmail/gmail-api-client.service';
import { CalendarApiClient } from '../src/calendar/calendar-api-client.service';
import { EmailDraftService } from '../src/email-reply/email-draft.service';
import { EmailCommitmentExtractionService } from '../src/email-reply/email-commitment-extraction.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { EmailSyncService } from '../src/email-sync/email-sync.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';
import { buildFakeGmailOAuth } from './support/fake-gmail-oauth';
import { buildFakeGmailApiClient } from './support/fake-gmail-api-client';
import { buildFakeCalendarApiClient } from './support/fake-calendar-api-client';

describe('Email reply flow (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let emailSyncService: EmailSyncService;
  const firebaseUid1 = 'reply-user-1';
  const firebaseUid2 = 'reply-user-2';
  const authHeader = { Authorization: `Bearer test-uid:${firebaseUid1}` };
  const otherAuthHeader = { Authorization: `Bearer test-uid:${firebaseUid2}` };

  const fakeDraftService = { gerar: async () => ({ direto: 'Ok.', formal: 'Prezado, ok.', padrao: 'Combinado, ok.' }) };
  const fakeExtractionServiceWithCommitment = {
    extrair: async () => ({
      tituloCompromisso: 'Enviar relatório',
      dataHoraLimite: '2026-09-01T15:00:00',
      antecedenciaMinutos: 1440,
    }),
  };

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
      .overrideProvider(CalendarApiClient)
      .useValue(buildFakeCalendarApiClient())
      .overrideProvider(EmailDraftService)
      .useValue(fakeDraftService)
      .overrideProvider(EmailCommitmentExtractionService)
      .useValue(fakeExtractionServiceWithCommitment)
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

  it('generates drafts, sends a reply, extracts a commitment, and confirms a calendar event', async () => {
    await request(app.getHttpServer()).post('/users/me').set(authHeader).send({ nome: 'Usuário Reply' }).expect(201);
    await request(app.getHttpServer())
      .post('/gmail/connect')
      .set(authHeader)
      .send({ serverAuthCode: 'test-code-1' })
      .expect(201);

    const user1 = await prisma.user.findUniqueOrThrow({ where: { firebaseUid: firebaseUid1 } });
    await emailSyncService.syncUser(user1.id);
    const summaries = await request(app.getHttpServer()).get('/resumos-email').set(authHeader).expect(200);
    const emailId = summaries.body[0].id as string;

    const drafts = await request(app.getHttpServer())
      .post(`/resumos-email/${emailId}/rascunhos`)
      .set(authHeader)
      .expect(201);
    expect(drafts.body).toEqual({ direto: 'Ok.', formal: 'Prezado, ok.', padrao: 'Combinado, ok.' });

    const sendResult = await request(app.getHttpServer())
      .post(`/resumos-email/${emailId}/enviar`)
      .set(authHeader)
      .send({ texto: 'Envio o relatório até segunda às 15h.' })
      .expect(201);
    expect(sendResult.body.enviado).toBe(true);
    expect(sendResult.body.compromissoSugerido).toEqual({
      tituloCompromisso: 'Enviar relatório',
      dataHoraLimite: '2026-09-01T15:00:00',
      antecedenciaMinutos: 1440,
    });

    const confirmResult = await request(app.getHttpServer())
      .post('/resumos-email/compromissos/confirmar')
      .set(authHeader)
      .send(sendResult.body.compromissoSugerido)
      .expect(201);
    expect(confirmResult.body).toEqual({ agendado: true });

    // O app envia a data com o offset do dispositivo (é isso que evita o evento cair no fuso do
    // servidor); a validação do DTO precisa aceitar essa forma.
    const confirmComFuso = await request(app.getHttpServer())
      .post('/resumos-email/compromissos/confirmar')
      .set(authHeader)
      .send({
        ...sendResult.body.compromissoSugerido,
        dataHoraLimite: '2026-09-01T15:00:00.000-03:00',
      })
      .expect(201);
    expect(confirmComFuso.body).toEqual({ agendado: true });
  });

  it('rejects drafts/send for a tenant without the send scope, and confirm without the calendar scope', async () => {
    await request(app.getHttpServer()).post('/users/me').set(otherAuthHeader).send({ nome: 'Sem Escopo' }).expect(201);
    // Connect with only the readonly scope granted (send and calendar denied by the user in the
    // consent screen) — exercised via the fake OAuth's configurable `scope` option from Task 2.
    const moduleWithNarrowScope: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(FIREBASE_ADMIN)
      .useValue(buildFakeFirebaseAdmin())
      .overrideProvider(GmailOAuthService)
      .useValue(buildFakeGmailOAuth({ scope: 'https://www.googleapis.com/auth/gmail.readonly' }))
      .overrideProvider(GmailApiClient)
      .useValue(buildFakeGmailApiClient())
      .overrideProvider(CalendarApiClient)
      .useValue(buildFakeCalendarApiClient())
      .compile();
    const narrowApp = moduleWithNarrowScope.createNestApplication();
    narrowApp.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
    await narrowApp.init();

    await request(narrowApp.getHttpServer())
      .post('/gmail/connect')
      .set(otherAuthHeader)
      .send({ serverAuthCode: 'test-code-2' })
      .expect(201);

    const user2 = await prisma.user.findUniqueOrThrow({ where: { firebaseUid: firebaseUid2 } });
    const narrowEmailSync = moduleWithNarrowScope.get(EmailSyncService);
    await narrowEmailSync.syncUser(user2.id);
    const summaries2 = await request(narrowApp.getHttpServer()).get('/resumos-email').set(otherAuthHeader).expect(200);
    const otherEmailId = summaries2.body[0].id as string;

    await request(narrowApp.getHttpServer())
      .post(`/resumos-email/${otherEmailId}/rascunhos`)
      .set(otherAuthHeader)
      .expect(403);
    await request(narrowApp.getHttpServer())
      .post(`/resumos-email/${otherEmailId}/enviar`)
      .set(otherAuthHeader)
      .send({ texto: 'texto' })
      .expect(403);
    await request(narrowApp.getHttpServer())
      .post('/resumos-email/compromissos/confirmar')
      .set(otherAuthHeader)
      .send({ tituloCompromisso: 'X', dataHoraLimite: '2026-09-01T15:00:00', antecedenciaMinutos: 60 })
      .expect(403);

    await narrowApp.close();
  });

  it("rejects drafts/send for an e-mail id that belongs to a different tenant", async () => {
    const summariesTenant1 = await request(app.getHttpServer()).get('/resumos-email').set(authHeader).expect(200);
    const tenant1EmailId = summariesTenant1.body[0].id as string;

    await request(app.getHttpServer())
      .post(`/resumos-email/${tenant1EmailId}/rascunhos`)
      .set(otherAuthHeader)
      .expect(404);
  });
});
