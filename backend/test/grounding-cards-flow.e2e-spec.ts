import 'dotenv/config';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';

describe('Grounding cards (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  const firebaseUidAdmin = 'grounding-cards-admin-user';
  const firebaseUidUserA = 'grounding-cards-user-a';
  const firebaseUidUserB = 'grounding-cards-user-b';
  const adminAuthHeader = { Authorization: `Bearer test-uid:${firebaseUidAdmin}` };
  const userAAuthHeader = { Authorization: `Bearer test-uid:${firebaseUidUserA}` };
  const userBAuthHeader = { Authorization: `Bearer test-uid:${firebaseUidUserB}` };

  const cardPayload = {
    titulo: 'Respiração 4-7-8',
    categoria: 'RESPIRACAO',
    conteudo: 'Inspire por 4 segundos, segure por 7, expire por 8.',
  };

  let cardId: string;

  beforeAll(async () => {
    const moduleRef: TestingModule = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(FIREBASE_ADMIN)
      .useValue(buildFakeFirebaseAdmin())
      .compile();

    app = moduleRef.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
    await app.init();
    prisma = moduleRef.get(PrismaService);

    await request(app.getHttpServer()).post('/users/me').set(adminAuthHeader).send({ nome: 'Admin User' }).expect(201);
    await prisma.user.update({ where: { firebaseUid: firebaseUidAdmin }, data: { isAdmin: true } });
    await request(app.getHttpServer()).post('/users/me').set(userAAuthHeader).send({ nome: 'User A' }).expect(201);
    await request(app.getHttpServer()).post('/users/me').set(userBAuthHeader).send({ nome: 'User B' }).expect(201);

    const created = await request(app.getHttpServer())
      .post('/admin/grounding-cards')
      .set(adminAuthHeader)
      .send(cardPayload)
      .expect(201);
    cardId = created.body.id;
  });

  afterAll(async () => {
    await prisma.cardFavorito.deleteMany({ where: { cardId } });
    await prisma.groundingCard.deleteMany({ where: { titulo: cardPayload.titulo } });
    await prisma.user.deleteMany({
      where: { firebaseUid: { in: [firebaseUidAdmin, firebaseUidUserA, firebaseUidUserB] } },
    });
    await app.close();
  });

  it('rejects a non-admin authenticated user with 403 on all four admin routes', async () => {
    await request(app.getHttpServer()).get('/admin/grounding-cards').set(userAAuthHeader).expect(403);
    await request(app.getHttpServer())
      .post('/admin/grounding-cards')
      .set(userAAuthHeader)
      .send(cardPayload)
      .expect(403);
    await request(app.getHttpServer())
      .patch(`/admin/grounding-cards/${cardId}`)
      .set(userAAuthHeader)
      .send(cardPayload)
      .expect(403);
    await request(app.getHttpServer()).delete(`/admin/grounding-cards/${cardId}`).set(userAAuthHeader).expect(403);
  });

  it('rejects an unauthenticated request with 401', async () => {
    await request(app.getHttpServer()).get('/admin/grounding-cards').expect(401);
  });

  it('lists the card in the public endpoint and filters by categoria', async () => {
    const all = await request(app.getHttpServer()).get('/grounding-cards').set(userAAuthHeader).expect(200);
    expect(all.body.some((c: { id: string }) => c.id === cardId)).toBe(true);

    const filtered = await request(app.getHttpServer())
      .get('/grounding-cards')
      .query({ categoria: 'RESPIRACAO' })
      .set(userAAuthHeader)
      .expect(200);
    expect(filtered.body.some((c: { id: string }) => c.id === cardId)).toBe(true);

    const otherCategoria = await request(app.getHttpServer())
      .get('/grounding-cards')
      .query({ categoria: 'MOVIMENTO' })
      .set(userAAuthHeader)
      .expect(200);
    expect(otherCategoria.body.some((c: { id: string }) => c.id === cardId)).toBe(false);
  });

  it('favoritar is idempotent and scoped per user, never leaking between users', async () => {
    await request(app.getHttpServer()).post(`/grounding-cards/${cardId}/favoritar`).set(userAAuthHeader).expect(201);
    await request(app.getHttpServer()).post(`/grounding-cards/${cardId}/favoritar`).set(userAAuthHeader).expect(201);

    const favoritosA = await request(app.getHttpServer())
      .get('/grounding-cards/favoritos')
      .set(userAAuthHeader)
      .expect(200);
    expect(favoritosA.body).toHaveLength(1);
    expect(favoritosA.body[0].id).toBe(cardId);

    const favoritosB = await request(app.getHttpServer())
      .get('/grounding-cards/favoritos')
      .set(userBAuthHeader)
      .expect(200);
    expect(favoritosB.body).toHaveLength(0);

    await request(app.getHttpServer()).delete(`/grounding-cards/${cardId}/favoritar`).set(userAAuthHeader).expect(200);

    const favoritosAfterRemove = await request(app.getHttpServer())
      .get('/grounding-cards/favoritos')
      .set(userAAuthHeader)
      .expect(200);
    expect(favoritosAfterRemove.body).toHaveLength(0);
  });

  it('deactivating a card keeps it in the DB and admin list, but hides it from the public endpoint', async () => {
    await request(app.getHttpServer()).delete(`/admin/grounding-cards/${cardId}`).set(adminAuthHeader).expect(200);

    const dbRecord = await prisma.groundingCard.findUnique({ where: { id: cardId } });
    expect(dbRecord?.ativo).toBe(false);

    const publicList = await request(app.getHttpServer()).get('/grounding-cards').set(userAAuthHeader).expect(200);
    expect(publicList.body.some((c: { id: string }) => c.id === cardId)).toBe(false);

    const adminList = await request(app.getHttpServer()).get('/admin/grounding-cards').set(adminAuthHeader).expect(200);
    expect(adminList.body.some((c: { id: string }) => c.id === cardId)).toBe(true);

    const reactivated = await request(app.getHttpServer())
      .patch(`/admin/grounding-cards/${cardId}`)
      .set(adminAuthHeader)
      .send({ ...cardPayload, ativo: true })
      .expect(200);
    expect(reactivated.body.ativo).toBe(true);

    const publicListAfterReactivate = await request(app.getHttpServer())
      .get('/grounding-cards')
      .set(userAAuthHeader)
      .expect(200);
    expect(publicListAfterReactivate.body.some((c: { id: string }) => c.id === cardId)).toBe(true);
  });
});
