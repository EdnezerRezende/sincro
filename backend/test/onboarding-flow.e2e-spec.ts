import 'dotenv/config';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';

interface MeResponseBody {
  hasSensoryProfile: boolean;
  trustedContactCount: number;
}

interface TrustedContactResponseBody {
  id: string;
}

interface EmergencyMessageResponseBody {
  contactName: string;
  waUrl: string;
}

describe('Onboarding flow (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let contactId: string;
  const testFirebaseUid = 'e2e-user-1';
  const otherFirebaseUid = 'e2e-user-2';
  const authHeader = { Authorization: `Bearer test-uid:${testFirebaseUid}` };
  const otherAuthHeader = {
    Authorization: `Bearer test-uid:${otherFirebaseUid}`,
  };

  beforeAll(async () => {
    const moduleRef: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(FIREBASE_ADMIN)
      .useValue(buildFakeFirebaseAdmin())
      .compile();

    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }),
    );
    await app.init();
    prisma = moduleRef.get(PrismaService);
  });

  afterAll(async () => {
    for (const uid of [testFirebaseUid, otherFirebaseUid]) {
      const user = await prisma.user.findUnique({
        where: { firebaseUid: uid },
      });
      if (user) {
        await prisma.trustedContact.deleteMany({ where: { userId: user.id } });
        await prisma.sensoryProfile.deleteMany({ where: { userId: user.id } });
        await prisma.user.delete({ where: { id: user.id } });
      }
    }
    await app.close();
  });

  it('completes the full onboarding, anamnese, and emergency-message flow', async () => {
    await request(app.getHttpServer())
      .post('/users/me')
      .set(authHeader)
      .send({ nome: 'Usuário E2E' })
      .expect(201);

    const meAfterSignup = await request(app.getHttpServer())
      .get('/users/me')
      .set(authHeader)
      .expect(200);
    const meAfterSignupBody = meAfterSignup.body as MeResponseBody;
    expect(meAfterSignupBody.hasSensoryProfile).toBe(false);
    expect(meAfterSignupBody.trustedContactCount).toBe(0);

    await request(app.getHttpServer())
      .put('/sensory-profile')
      .set(authHeader)
      .send({
        dados: {
          toleranciaNotificacao: 'SILENCIOSAS',
          gatilhos: ['Abrir o app do banco'],
        },
      })
      .expect(200);

    const contactResponse = await request(app.getHttpServer())
      .post('/trusted-contacts')
      .set(authHeader)
      .send({
        nome: 'Dra. Marina',
        relacao: 'PSICOLOGO',
        whatsapp: '+5511999999999',
        prioridade: 0,
        consentimentoAceito: true,
      })
      .expect(201);
    contactId = (contactResponse.body as TrustedContactResponseBody).id;

    const meAfterOnboarding = await request(app.getHttpServer())
      .get('/users/me')
      .set(authHeader)
      .expect(200);
    const meAfterOnboardingBody = meAfterOnboarding.body as MeResponseBody;
    expect(meAfterOnboardingBody.hasSensoryProfile).toBe(true);
    expect(meAfterOnboardingBody.trustedContactCount).toBe(1);

    const emergencyResponse = await request(app.getHttpServer())
      .post('/emergency/message')
      .set(authHeader)
      .send({ contactId })
      .expect(201);
    const emergencyBody =
      emergencyResponse.body as EmergencyMessageResponseBody;

    expect(emergencyBody.contactName).toBe('Dra. Marina');
    expect(emergencyBody.waUrl).toContain('https://wa.me/5511999999999?text=');
  });

  it('rejects requests without a valid Firebase token', async () => {
    await request(app.getHttpServer()).get('/users/me').expect(401);
  });

  it('does not leak trusted contacts across firebaseUid tenants', async () => {
    await request(app.getHttpServer())
      .post('/users/me')
      .set(otherAuthHeader)
      .send({ nome: 'Outro Usuário E2E' })
      .expect(201);

    const otherMe = await request(app.getHttpServer())
      .get('/users/me')
      .set(otherAuthHeader)
      .expect(200);
    const otherMeBody = otherMe.body as MeResponseBody;
    expect(otherMeBody.trustedContactCount).toBe(0);

    await request(app.getHttpServer())
      .post('/emergency/message')
      .set(otherAuthHeader)
      .send({ contactId })
      .expect(404);
  });
});
