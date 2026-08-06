import 'dotenv/config';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';

describe('Professionals admin authorization (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  const firebaseUidAdmin = 'professionals-admin-user';
  const firebaseUidNonAdmin = 'professionals-non-admin-user';
  const adminAuthHeader = { Authorization: `Bearer test-uid:${firebaseUidAdmin}` };
  const nonAdminAuthHeader = { Authorization: `Bearer test-uid:${firebaseUidNonAdmin}` };

  const professionalPayload = {
    nome: 'Dra. Marina Souza',
    tags: ['TEA', 'TDAH'],
    cidade: 'São Paulo',
    latitude: -23.5505,
    longitude: -46.6333,
    telefone: '+5511999999999',
    bio: 'Psicóloga especialista em neurodivergência.',
  };

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

    await request(app.getHttpServer())
      .post('/users/me')
      .set(nonAdminAuthHeader)
      .send({ nome: 'Non Admin User' })
      .expect(201);
  });

  afterAll(async () => {
    await prisma.professional.deleteMany({ where: { nome: professionalPayload.nome } });
    await prisma.user.deleteMany({ where: { firebaseUid: { in: [firebaseUidAdmin, firebaseUidNonAdmin] } } });
    await app.close();
  });

  it('rejects a non-admin authenticated user with 403 on all four admin routes', async () => {
    await request(app.getHttpServer())
      .get('/admin/professionals')
      .set(nonAdminAuthHeader)
      .expect(403);

    await request(app.getHttpServer())
      .post('/admin/professionals')
      .set(nonAdminAuthHeader)
      .send(professionalPayload)
      .expect(403);

    await request(app.getHttpServer())
      .patch('/admin/professionals/00000000-0000-0000-0000-000000000000')
      .set(nonAdminAuthHeader)
      .send(professionalPayload)
      .expect(403);

    await request(app.getHttpServer())
      .delete('/admin/professionals/00000000-0000-0000-0000-000000000000')
      .set(nonAdminAuthHeader)
      .expect(403);
  });

  it('rejects an unauthenticated request with 401 on all four admin routes', async () => {
    await request(app.getHttpServer()).get('/admin/professionals').expect(401);
    await request(app.getHttpServer()).post('/admin/professionals').send(professionalPayload).expect(401);
    await request(app.getHttpServer())
      .patch('/admin/professionals/00000000-0000-0000-0000-000000000000')
      .send(professionalPayload)
      .expect(401);
    await request(app.getHttpServer())
      .delete('/admin/professionals/00000000-0000-0000-0000-000000000000')
      .expect(401);
  });

  it('allows an admin user to list and create a professional', async () => {
    await request(app.getHttpServer()).get('/admin/professionals').set(adminAuthHeader).expect(200);

    const created = await request(app.getHttpServer())
      .post('/admin/professionals')
      .set(adminAuthHeader)
      .send(professionalPayload)
      .expect(201);

    expect(created.body.id).toBeDefined();
    expect(created.body.nome).toBe(professionalPayload.nome);
    expect(created.body.ativo).toBe(true);
  });

  it('deactivating a professional keeps it in the DB and in admin list, but hides it from public search', async () => {
    const created = await request(app.getHttpServer())
      .post('/admin/professionals')
      .set(adminAuthHeader)
      .send({ ...professionalPayload, nome: 'Dr. João Deactivate Test' })
      .expect(201);
    const professionalId = created.body.id;

    const beforeSearch = await request(app.getHttpServer())
      .get('/professionals/search')
      .set(adminAuthHeader)
      .query({ lat: professionalPayload.latitude, lng: professionalPayload.longitude })
      .expect(200);
    expect(beforeSearch.body.some((p: { id: string }) => p.id === professionalId)).toBe(true);

    await request(app.getHttpServer())
      .delete(`/admin/professionals/${professionalId}`)
      .set(adminAuthHeader)
      .expect(200);

    const dbRecord = await prisma.professional.findUnique({ where: { id: professionalId } });
    expect(dbRecord).not.toBeNull();
    expect(dbRecord?.ativo).toBe(false);

    const afterSearch = await request(app.getHttpServer())
      .get('/professionals/search')
      .set(adminAuthHeader)
      .query({ lat: professionalPayload.latitude, lng: professionalPayload.longitude })
      .expect(200);
    expect(afterSearch.body.some((p: { id: string }) => p.id === professionalId)).toBe(false);

    const adminList = await request(app.getHttpServer()).get('/admin/professionals').set(adminAuthHeader).expect(200);
    const adminRecord = adminList.body.find((p: { id: string }) => p.id === professionalId);
    expect(adminRecord).toBeDefined();
    expect(adminRecord.ativo).toBe(false);

    await prisma.professional.deleteMany({ where: { id: professionalId } });
  });
});
