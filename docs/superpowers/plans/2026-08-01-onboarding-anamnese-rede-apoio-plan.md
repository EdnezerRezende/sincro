# Sincro — Onboarding, Anamnese e Rede de Apoio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Sincro Phase 1 foundation — Firebase-authenticated onboarding, a sensory/executive anamnese wizard, and a trusted-contacts network with a working "notify support network" WhatsApp handoff — as a NestJS API backed by PostgreSQL, and a Flutter mobile client.

**Architecture:** Monorepo with `backend/` (NestJS + Prisma + PostgreSQL) and `mobile/` (Flutter + Riverpod). Firebase Authentication issues ID tokens; the NestJS API verifies them via `firebase-admin` and derives `user_id` server-side for every query — the client never supplies a tenant identifier directly. Business data (sensory profile, trusted contacts) lives only in Postgres, never in Firebase.

**Tech Stack:** NestJS 10, Prisma 5, PostgreSQL 16 (`pgvector/pgvector:pg16` image), Firebase Admin SDK, Flutter 3.x, Riverpod, Dio, firebase_auth, url_launcher, Jest/Supertest, flutter_test/mocktail.

## Status: ✅ Implemented (Tasks 1–15, all reviewed)

All 14 original tasks plus one task added after final review (Task 15) are implemented, individually reviewed (spec compliance + code quality), and passing. Branch `worktree-sincro-onboarding-anamnese-rede-apoio` is pushed to `origin`, PR pending creation.

**Final test status:**
- Backend: `npm test` 16/16 unit tests passing, `npm run test:e2e` 5/5 passing (incl. cross-tenant isolation).
- Mobile: `flutter test` 20/20 passing, `flutter analyze` clean.

**Version drift from this plan's assumptions (discovered and adapted for during implementation):**
- **Prisma resolved to `^7.9.1`, not `5`.** `datasource.url` in `schema.prisma` is no longer supported in v7 (moved to `backend/prisma.config.ts`), and `PrismaClient` requires an explicit driver adapter (`@prisma/adapter-pg`) built in `PrismaService`'s constructor rather than a bare `new PrismaClient()`. Also required `import 'dotenv/config'` as the first line of `backend/src/main.ts` so `DATABASE_URL` is actually loaded into `process.env` before the adapter reads it (Task 2, fix round 1).
- **`flutter_riverpod` resolved to `^3.3.2`,** whose idiomatic API is `Notifier`/`NotifierProvider`, not the classic `StateNotifier`/`StateNotifierProvider` this plan's code snippets use. Fixed via a consistent pattern across every notifier: a plain Dart state-holder class (matches the brief's test contract) wrapped by a thin `Notifier` subclass for Riverpod wiring (see `AnamneseNotifier` + `_AnamneseNotifierWrapper` in `mobile/lib/features/onboarding/anamnese/anamnese_providers.dart`).

**Final whole-branch review (after Task 14) found and fixed two integration-level Critical bugs no single task review could see:**
1. `signup_screen.dart` navigated to an unregistered route (`/onboarding` instead of `/onboarding-router`) — every signup dead-ended.
2. `UsersRepository.upsertMe()` had zero callers anywhere in the mobile app, so no `usuarios` Postgres row was ever created for a new user — `OnboardingRouterScreen` 404'd forever.

Also fixed in the same pass: a zero-contacts navigation trap, missing WhatsApp number format validation (client + server), a broken pre-existing e2e scaffold file, a missing DB index, and several resource-leak/type-safety polish items. See the `## Plan Self-Review Notes` and the git history (commits `9d2c984..3320dbc`) for the full list.

**Task 15 (added post-review):** the design spec's "edit/delete your profile and contacts at any time" requirement (objective 5, LGPD *direito de exclusão*) was never assigned to any of the original 14 tasks — `/home` had no outgoing navigation at all. Task 15 added a `DELETE /sensory-profile` endpoint, a settings screen (edit/delete sensory profile with existing-answers reload, manage/delete trusted contacts, sign out), and wired it up from `/home`. See the new Task 15 section below.

## Global Constraints

- Every table/column name in Postgres uses the Portuguese names fixed in the spec: `usuarios`, `perfis_sensoriais`, `contatos_confianca`, `firebase_uid`, `dados`, `versao`, `relacao`, `whatsapp`, `prioridade`, `consentimento_aceito_em`.
- Tenant isolation is enforced in the application layer only: every repository/service call scopes by `user_id` derived from the verified Firebase token — never from a client-supplied parameter.
- No business data (sensory profile, contacts) is ever written to Firebase — Firebase is authentication only.
- The emergency contact flow never sends a WhatsApp message automatically — it only opens a pre-filled `wa.me` link that the user confirms inside WhatsApp.
- Consent (`consentimentoAceito`) is mandatory per contact; the API rejects contact creation without it.
- Relação enum values are exactly: `PSICOLOGO`, `PSIQUIATRA`, `T.O.`, `FAMILIAR`, `OUTRO`.

---

## Backend (NestJS)

### Task 1: NestJS project scaffold + local PostgreSQL

**Files:**
- Create: `backend/` (via Nest CLI scaffold)
- Create: `backend/docker-compose.yml`
- Create: `backend/.env.example`
- Create: `backend/.env` (local only, gitignored)

**Interfaces:**
- Produces: a running NestJS app on port 3000, a running Postgres instance on port 5432 reachable at the `DATABASE_URL` in `.env`.

- [x] **Step 1: Scaffold the NestJS project**

Run from the repo root:
```bash
npx @nestjs/cli new backend --package-manager npm --skip-git
```

- [x] **Step 2: Install backend dependencies**

```bash
cd backend
npm install prisma @prisma/client class-validator class-transformer firebase-admin
npm install -D @types/supertest
```

- [x] **Step 3: Create the local Postgres via docker-compose**

`backend/docker-compose.yml`:
```yaml
version: '3.8'
services:
  postgres:
    image: pgvector/pgvector:pg16
    restart: unless-stopped
    environment:
      POSTGRES_USER: sincro
      POSTGRES_PASSWORD: sincro_dev_password
      POSTGRES_DB: sincro_dev
    ports:
      - "5432:5432"
    volumes:
      - sincro_postgres_data:/var/lib/postgresql/data

volumes:
  sincro_postgres_data:
```

- [x] **Step 4: Create environment files**

`backend/.env.example`:
```
DATABASE_URL="postgresql://sincro:sincro_dev_password@localhost:5432/sincro_dev"
FIREBASE_PROJECT_ID=""
FIREBASE_CLIENT_EMAIL=""
FIREBASE_PRIVATE_KEY=""
```

Copy it to `backend/.env` with the same values (local dev only — real Firebase credentials are added in Task 3).

- [x] **Step 5: Start Postgres and verify connectivity**

```bash
docker compose -f backend/docker-compose.yml up -d
docker exec -it $(docker compose -f backend/docker-compose.yml ps -q postgres) psql -U sincro -d sincro_dev -c "SELECT 1;"
```
Expected: query returns `1`.

- [x] **Step 6: Add `.gitignore` entries and commit**

Append to `backend/.gitignore` (created by Nest scaffold): `.env`

```bash
git add backend package.json backend/docker-compose.yml backend/.env.example backend/.gitignore 2>/dev/null
git add backend/
git commit -m "chore: scaffold NestJS backend with local Postgres via docker-compose"
```

---

### Task 2: Prisma schema and initial migration

**Files:**
- Create: `backend/prisma/schema.prisma`
- Create: `backend/src/prisma/prisma.service.ts`
- Create: `backend/src/prisma/prisma.module.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Produces: `PrismaService` (importable from `src/prisma/prisma.service.ts`), Prisma models `User`, `SensoryProfile`, `TrustedContact` with generated client types.

- [x] **Step 1: Initialize Prisma**

```bash
cd backend
npx prisma init --datasource-provider postgresql
```
This overwrites `prisma/schema.prisma` — replace it in the next step.

- [x] **Step 2: Write the schema**

`backend/prisma/schema.prisma`:
```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id              String           @id @default(uuid())
  firebaseUid     String           @unique @map("firebase_uid")
  nome            String
  createdAt       DateTime         @default(now()) @map("created_at")
  sensoryProfile  SensoryProfile?
  trustedContacts TrustedContact[]

  @@map("usuarios")
}

model SensoryProfile {
  id        String   @id @default(uuid())
  userId    String   @unique @map("user_id")
  user      User     @relation(fields: [userId], references: [id])
  dados     Json
  versao    Int      @default(1)
  updatedAt DateTime @updatedAt @map("updated_at")

  @@map("perfis_sensoriais")
}

model TrustedContact {
  id                    String   @id @default(uuid())
  userId                String   @map("user_id")
  user                  User     @relation(fields: [userId], references: [id])
  nome                  String
  relacao               String
  whatsapp              String
  prioridade            Int      @default(0)
  consentimentoAceitoEm DateTime @map("consentimento_aceito_em")
  createdAt             DateTime @default(now()) @map("created_at")

  @@map("contatos_confianca")
}
```

- [x] **Step 3: Run the initial migration**

```bash
npx prisma migrate dev --name init
```
Expected: migration applied, Prisma Client generated, no errors.

- [x] **Step 4: Create PrismaService and PrismaModule**

`backend/src/prisma/prisma.service.ts`:
```typescript
import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

`backend/src/prisma/prisma.module.ts`:
```typescript
import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

- [x] **Step 5: Register PrismaModule in AppModule**

Modify `backend/src/app.module.ts` to import `PrismaModule`:
```typescript
import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';

@Module({
  imports: [PrismaModule],
})
export class AppModule {}
```

- [x] **Step 6: Verify the app still boots**

```bash
npm run start:dev
```
Expected: `Nest application successfully started` with no errors, then stop it (Ctrl+C).

- [x] **Step 7: Commit**

```bash
git add backend/prisma backend/src/prisma backend/src/app.module.ts
git commit -m "feat: add Prisma schema and initial migration for usuarios, perfis_sensoriais, contatos_confianca"
```

---

### Task 3: Firebase Auth guard

**Files:**
- Create: `backend/src/auth/firebase-admin.provider.ts`
- Create: `backend/src/auth/firebase-auth.guard.ts`
- Create: `backend/src/auth/auth.module.ts`
- Create: `backend/src/common/current-firebase-uid.decorator.ts`
- Test: `backend/src/auth/firebase-auth.guard.spec.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Consumes: none (first auth layer).
- Produces: `FirebaseAuthGuard` (class, `@UseGuards(FirebaseAuthGuard)`), `@CurrentFirebaseUid()` param decorator returning `string`, `FIREBASE_ADMIN` DI token.

- [x] **Step 1: Write the failing guard test**

`backend/src/auth/firebase-auth.guard.spec.ts`:
```typescript
import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { FirebaseAuthGuard } from './firebase-auth.guard';
import { FIREBASE_ADMIN } from './firebase-admin.provider';

function buildContext(headers: Record<string, string>): ExecutionContext {
  const request: any = { headers };
  return {
    switchToHttp: () => ({ getRequest: () => request }),
  } as ExecutionContext;
}

describe('FirebaseAuthGuard', () => {
  it('throws UnauthorizedException when there is no bearer token', async () => {
    const fakeAdmin: any = { auth: () => ({ verifyIdToken: jest.fn() }) };
    const guard = new FirebaseAuthGuard(fakeAdmin);
    const context = buildContext({});

    await expect(guard.canActivate(context)).rejects.toThrow(UnauthorizedException);
  });

  it('sets request.firebaseUid and returns true for a valid token', async () => {
    const verifyIdToken = jest.fn().mockResolvedValue({ uid: 'user-123' });
    const fakeAdmin: any = { auth: () => ({ verifyIdToken }) };
    const guard = new FirebaseAuthGuard(fakeAdmin);
    const context = buildContext({ authorization: 'Bearer valid-token' });

    const result = await guard.canActivate(context);

    expect(result).toBe(true);
    expect(context.switchToHttp().getRequest().firebaseUid).toBe('user-123');
    expect(verifyIdToken).toHaveBeenCalledWith('valid-token');
  });

  it('throws UnauthorizedException when the token is invalid', async () => {
    const verifyIdToken = jest.fn().mockRejectedValue(new Error('bad token'));
    const fakeAdmin: any = { auth: () => ({ verifyIdToken }) };
    const guard = new FirebaseAuthGuard(fakeAdmin);
    const context = buildContext({ authorization: 'Bearer bad-token' });

    await expect(guard.canActivate(context)).rejects.toThrow(UnauthorizedException);
  });
});
```

- [x] **Step 2: Run test to verify it fails**

```bash
npx jest src/auth/firebase-auth.guard.spec.ts
```
Expected: FAIL — `Cannot find module './firebase-auth.guard'`.

- [x] **Step 3: Implement the Firebase Admin provider**

`backend/src/auth/firebase-admin.provider.ts`:
```typescript
import { Provider } from '@nestjs/common';
import * as admin from 'firebase-admin';

export const FIREBASE_ADMIN = 'FIREBASE_ADMIN';

export const firebaseAdminProvider: Provider = {
  provide: FIREBASE_ADMIN,
  useFactory: (): typeof admin => {
    if (admin.apps.length === 0) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
          privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        }),
      });
    }
    return admin;
  },
};
```

- [x] **Step 4: Implement the guard and decorator**

`backend/src/auth/firebase-auth.guard.ts`:
```typescript
import { CanActivate, ExecutionContext, Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { FIREBASE_ADMIN } from './firebase-admin.provider';
import * as admin from 'firebase-admin';

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  constructor(@Inject(FIREBASE_ADMIN) private readonly firebaseAdmin: typeof admin) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader: string | undefined = request.headers['authorization'];

    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing bearer token');
    }

    const idToken = authHeader.substring('Bearer '.length);

    try {
      const decoded = await this.firebaseAdmin.auth().verifyIdToken(idToken);
      request.firebaseUid = decoded.uid;
      return true;
    } catch {
      throw new UnauthorizedException('Invalid token');
    }
  }
}
```

`backend/src/common/current-firebase-uid.decorator.ts`:
```typescript
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const CurrentFirebaseUid = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): string => {
    const request = ctx.switchToHttp().getRequest();
    return request.firebaseUid;
  },
);
```

`backend/src/auth/auth.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { firebaseAdminProvider } from './firebase-admin.provider';
import { FirebaseAuthGuard } from './firebase-auth.guard';

@Module({
  providers: [firebaseAdminProvider, FirebaseAuthGuard],
  exports: [firebaseAdminProvider, FirebaseAuthGuard],
})
export class AuthModule {}
```

- [x] **Step 5: Register AuthModule in AppModule**

Modify `backend/src/app.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';

@Module({
  imports: [PrismaModule, AuthModule],
})
export class AppModule {}
```

- [x] **Step 6: Run test to verify it passes**

```bash
npx jest src/auth/firebase-auth.guard.spec.ts
```
Expected: PASS, 3 tests.

- [x] **Step 7: Commit**

```bash
git add backend/src/auth backend/src/common backend/src/app.module.ts
git commit -m "feat: add Firebase Auth guard and current-uid decorator"
```

---

### Task 4: Users module (onboarding identity)

**Files:**
- Create: `backend/src/users/dto/upsert-user.dto.ts`
- Create: `backend/src/users/users.service.ts`
- Create: `backend/src/users/users.controller.ts`
- Create: `backend/src/users/users.module.ts`
- Test: `backend/src/users/users.service.spec.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Consumes: `PrismaService` (Task 2), `FirebaseAuthGuard` + `CurrentFirebaseUid` (Task 3).
- Produces: `UsersService.upsertByFirebaseUid(firebaseUid: string, nome: string): Promise<User>`, `UsersService.getByFirebaseUidOrThrow(firebaseUid: string): Promise<User>`, `UsersService.getOnboardingStatus(firebaseUid: string): Promise<{ userId, nome, hasSensoryProfile, trustedContactCount }>`. Routes: `POST /users/me`, `GET /users/me`.

- [x] **Step 1: Write the failing service test**

`backend/src/users/users.service.spec.ts`:
```typescript
import { NotFoundException } from '@nestjs/common';
import { UsersService } from './users.service';

function buildPrismaMock() {
  return {
    user: { upsert: jest.fn(), findUnique: jest.fn() },
    sensoryProfile: { findUnique: jest.fn() },
    trustedContact: { count: jest.fn() },
  };
}

describe('UsersService', () => {
  it('upserts a user by firebaseUid', async () => {
    const prisma = buildPrismaMock();
    prisma.user.upsert.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', nome: 'Ana' });
    const service = new UsersService(prisma as any);

    const result = await service.upsertByFirebaseUid('fb1', 'Ana');

    expect(prisma.user.upsert).toHaveBeenCalledWith({
      where: { firebaseUid: 'fb1' },
      update: { nome: 'Ana' },
      create: { firebaseUid: 'fb1', nome: 'Ana' },
    });
    expect(result.nome).toBe('Ana');
  });

  it('throws NotFoundException when the user does not exist yet', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue(null);
    const service = new UsersService(prisma as any);

    await expect(service.getByFirebaseUidOrThrow('missing')).rejects.toThrow(NotFoundException);
  });

  it('builds onboarding status combining profile and contact count', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', nome: 'Ana' });
    prisma.sensoryProfile.findUnique.mockResolvedValue({ id: 'sp1' });
    prisma.trustedContact.count.mockResolvedValue(2);
    const service = new UsersService(prisma as any);

    const status = await service.getOnboardingStatus('fb1');

    expect(status).toEqual({
      userId: 'u1',
      nome: 'Ana',
      hasSensoryProfile: true,
      trustedContactCount: 2,
    });
  });
});
```

- [x] **Step 2: Run test to verify it fails**

```bash
npx jest src/users/users.service.spec.ts
```
Expected: FAIL — `Cannot find module './users.service'`.

- [x] **Step 3: Implement UsersService**

`backend/src/users/users.service.ts`:
```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async upsertByFirebaseUid(firebaseUid: string, nome: string) {
    return this.prisma.user.upsert({
      where: { firebaseUid },
      update: { nome },
      create: { firebaseUid, nome },
    });
  }

  async getByFirebaseUidOrThrow(firebaseUid: string) {
    const user = await this.prisma.user.findUnique({ where: { firebaseUid } });
    if (!user) {
      throw new NotFoundException('Usuário ainda não completou o cadastro inicial');
    }
    return user;
  }

  async getOnboardingStatus(firebaseUid: string) {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);
    const [sensoryProfile, trustedContactCount] = await Promise.all([
      this.prisma.sensoryProfile.findUnique({ where: { userId: user.id } }),
      this.prisma.trustedContact.count({ where: { userId: user.id } }),
    ]);

    return {
      userId: user.id,
      nome: user.nome,
      hasSensoryProfile: sensoryProfile !== null,
      trustedContactCount,
    };
  }
}
```

- [x] **Step 4: Run test to verify it passes**

```bash
npx jest src/users/users.service.spec.ts
```
Expected: PASS, 3 tests.

- [x] **Step 5: Add the DTO, controller, and module**

`backend/src/users/dto/upsert-user.dto.ts`:
```typescript
import { IsString, Length } from 'class-validator';

export class UpsertUserDto {
  @IsString()
  @Length(1, 100)
  nome: string;
}
```

`backend/src/users/users.controller.ts`:
```typescript
import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from './users.service';
import { UpsertUserDto } from './dto/upsert-user.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Post('me')
  async upsertMe(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: UpsertUserDto) {
    return this.usersService.upsertByFirebaseUid(firebaseUid, dto.nome);
  }

  @Get('me')
  async getMe(@CurrentFirebaseUid() firebaseUid: string) {
    return this.usersService.getOnboardingStatus(firebaseUid);
  }
}
```

`backend/src/users/users.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersService } from './users.service';
import { UsersController } from './users.controller';

@Module({
  imports: [AuthModule],
  providers: [UsersService],
  controllers: [UsersController],
  exports: [UsersService],
})
export class UsersModule {}
```

- [x] **Step 6: Register UsersModule in AppModule and enable global validation**

Modify `backend/src/main.ts` to add the global validation pipe:
```typescript
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
  await app.listen(3000);
}
bootstrap();
```

Modify `backend/src/app.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';

@Module({
  imports: [PrismaModule, AuthModule, UsersModule],
})
export class AppModule {}
```

- [x] **Step 7: Commit**

```bash
git add backend/src/users backend/src/main.ts backend/src/app.module.ts
git commit -m "feat: add users module with onboarding status endpoint"
```

---

### Task 5: Sensory profile module (anamnese)

**Files:**
- Create: `backend/src/sensory-profile/dto/upsert-sensory-profile.dto.ts`
- Create: `backend/src/sensory-profile/sensory-profile.service.ts`
- Create: `backend/src/sensory-profile/sensory-profile.controller.ts`
- Create: `backend/src/sensory-profile/sensory-profile.module.ts`
- Test: `backend/src/sensory-profile/sensory-profile.service.spec.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Consumes: `UsersService.getByFirebaseUidOrThrow` (Task 4), `PrismaService` (Task 2).
- Produces: `SensoryProfileService.upsert(firebaseUid: string, dados: Record<string, unknown>): Promise<SensoryProfile>`, `SensoryProfileService.get(firebaseUid: string): Promise<SensoryProfile | null>`. Routes: `PUT /sensory-profile`, `GET /sensory-profile`.

- [x] **Step 1: Write the failing service test**

`backend/src/sensory-profile/sensory-profile.service.spec.ts`:
```typescript
import { SensoryProfileService } from './sensory-profile.service';

describe('SensoryProfileService', () => {
  it('upserts the profile scoped to the resolved user id', async () => {
    const prisma = { sensoryProfile: { upsert: jest.fn().mockResolvedValue({ id: 'sp1' }) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new SensoryProfileService(prisma as any, usersService as any);

    const dados = { toleranciaNotificacao: 'SILENCIOSAS' };
    await service.upsert('fb1', dados);

    expect(usersService.getByFirebaseUidOrThrow).toHaveBeenCalledWith('fb1');
    expect(prisma.sensoryProfile.upsert).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      update: { dados },
      create: { userId: 'u1', dados },
    });
  });

  it('gets the profile scoped to the resolved user id', async () => {
    const prisma = { sensoryProfile: { findUnique: jest.fn().mockResolvedValue({ id: 'sp1' }) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new SensoryProfileService(prisma as any, usersService as any);

    const result = await service.get('fb1');

    expect(prisma.sensoryProfile.findUnique).toHaveBeenCalledWith({ where: { userId: 'u1' } });
    expect(result).toEqual({ id: 'sp1' });
  });
});
```

- [x] **Step 2: Run test to verify it fails**

```bash
npx jest src/sensory-profile/sensory-profile.service.spec.ts
```
Expected: FAIL — module not found.

- [x] **Step 3: Implement SensoryProfileService**

`backend/src/sensory-profile/sensory-profile.service.ts`:
```typescript
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';

@Injectable()
export class SensoryProfileService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
  ) {}

  async upsert(firebaseUid: string, dados: Record<string, unknown>) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.sensoryProfile.upsert({
      where: { userId: user.id },
      update: { dados },
      create: { userId: user.id, dados },
    });
  }

  async get(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.sensoryProfile.findUnique({ where: { userId: user.id } });
  }
}
```

- [x] **Step 4: Run test to verify it passes**

```bash
npx jest src/sensory-profile/sensory-profile.service.spec.ts
```
Expected: PASS, 2 tests.

- [x] **Step 5: Add DTO, controller, and module**

`backend/src/sensory-profile/dto/upsert-sensory-profile.dto.ts`:
```typescript
import { IsObject } from 'class-validator';

export class UpsertSensoryProfileDto {
  @IsObject()
  dados: Record<string, unknown>;
}
```

`backend/src/sensory-profile/sensory-profile.controller.ts`:
```typescript
import { Body, Controller, Get, Put, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { SensoryProfileService } from './sensory-profile.service';
import { UpsertSensoryProfileDto } from './dto/upsert-sensory-profile.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('sensory-profile')
export class SensoryProfileController {
  constructor(private readonly service: SensoryProfileService) {}

  @Put()
  async upsert(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: UpsertSensoryProfileDto) {
    return this.service.upsert(firebaseUid, dto.dados);
  }

  @Get()
  async get(@CurrentFirebaseUid() firebaseUid: string) {
    return this.service.get(firebaseUid);
  }
}
```

`backend/src/sensory-profile/sensory-profile.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { SensoryProfileService } from './sensory-profile.service';
import { SensoryProfileController } from './sensory-profile.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [SensoryProfileService],
  controllers: [SensoryProfileController],
})
export class SensoryProfileModule {}
```

- [x] **Step 6: Register the module in AppModule**

Modify `backend/src/app.module.ts` to add `SensoryProfileModule` to `imports`.

- [x] **Step 7: Commit**

```bash
git add backend/src/sensory-profile backend/src/app.module.ts
git commit -m "feat: add sensory profile module for the anamnese wizard"
```

---

### Task 6: Trusted contacts module

**Files:**
- Create: `backend/src/trusted-contacts/dto/create-trusted-contact.dto.ts`
- Create: `backend/src/trusted-contacts/trusted-contacts.service.ts`
- Create: `backend/src/trusted-contacts/trusted-contacts.controller.ts`
- Create: `backend/src/trusted-contacts/trusted-contacts.module.ts`
- Test: `backend/src/trusted-contacts/trusted-contacts.service.spec.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Consumes: `UsersService.getByFirebaseUidOrThrow` (Task 4), `PrismaService` (Task 2).
- Produces: `TrustedContactsService.create(firebaseUid, dto: CreateTrustedContactDto): Promise<TrustedContact>`, `.list(firebaseUid): Promise<TrustedContact[]>`, `.remove(firebaseUid, contactId): Promise<void>`. Routes: `POST /trusted-contacts`, `GET /trusted-contacts`, `DELETE /trusted-contacts/:id`. Consumed later by Task 7 (Emergency module needs `TrustedContact` shape: `id`, `nome`, `whatsapp`, `userId`).

- [x] **Step 1: Write the failing service test**

`backend/src/trusted-contacts/trusted-contacts.service.spec.ts`:
```typescript
import { BadRequestException } from '@nestjs/common';
import { TrustedContactsService } from './trusted-contacts.service';

function buildDto(overrides: Partial<any> = {}) {
  return {
    nome: 'Dra. Marina',
    relacao: 'PSICOLOGO',
    whatsapp: '+5511999999999',
    prioridade: 0,
    consentimentoAceito: true,
    ...overrides,
  };
}

describe('TrustedContactsService', () => {
  it('rejects creation without consent', async () => {
    const prisma = { trustedContact: { create: jest.fn() } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn() };
    const service = new TrustedContactsService(prisma as any, usersService as any);

    await expect(
      service.create('fb1', buildDto({ consentimentoAceito: false })),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.trustedContact.create).not.toHaveBeenCalled();
  });

  it('creates a contact scoped to the resolved user id with a consent timestamp', async () => {
    const prisma = { trustedContact: { create: jest.fn().mockResolvedValue({ id: 'c1' }) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new TrustedContactsService(prisma as any, usersService as any);

    await service.create('fb1', buildDto());

    expect(prisma.trustedContact.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        userId: 'u1',
        nome: 'Dra. Marina',
        relacao: 'PSICOLOGO',
        whatsapp: '+5511999999999',
        prioridade: 0,
        consentimentoAceitoEm: expect.any(Date),
      }),
    });
  });

  it('lists contacts ordered by prioridade, scoped to the resolved user id', async () => {
    const prisma = { trustedContact: { findMany: jest.fn().mockResolvedValue([]) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new TrustedContactsService(prisma as any, usersService as any);

    await service.list('fb1');

    expect(prisma.trustedContact.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      orderBy: { prioridade: 'asc' },
    });
  });

  it('removes a contact only if it belongs to the resolved user id', async () => {
    const prisma = { trustedContact: { deleteMany: jest.fn().mockResolvedValue({ count: 1 }) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new TrustedContactsService(prisma as any, usersService as any);

    await service.remove('fb1', 'c1');

    expect(prisma.trustedContact.deleteMany).toHaveBeenCalledWith({
      where: { id: 'c1', userId: 'u1' },
    });
  });
});
```

- [x] **Step 2: Run test to verify it fails**

```bash
npx jest src/trusted-contacts/trusted-contacts.service.spec.ts
```
Expected: FAIL — module not found.

- [x] **Step 3: Implement TrustedContactsService**

`backend/src/trusted-contacts/trusted-contacts.service.ts`:
```typescript
import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { CreateTrustedContactDto } from './dto/create-trusted-contact.dto';

@Injectable()
export class TrustedContactsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
  ) {}

  async create(firebaseUid: string, dto: CreateTrustedContactDto) {
    if (!dto.consentimentoAceito) {
      throw new BadRequestException('Consentimento é obrigatório para cadastrar um contato');
    }

    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);

    return this.prisma.trustedContact.create({
      data: {
        userId: user.id,
        nome: dto.nome,
        relacao: dto.relacao,
        whatsapp: dto.whatsapp,
        prioridade: dto.prioridade,
        consentimentoAceitoEm: new Date(),
      },
    });
  }

  async list(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.trustedContact.findMany({
      where: { userId: user.id },
      orderBy: { prioridade: 'asc' },
    });
  }

  async remove(firebaseUid: string, contactId: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    await this.prisma.trustedContact.deleteMany({
      where: { id: contactId, userId: user.id },
    });
  }
}
```

- [x] **Step 4: Run test to verify it passes**

```bash
npx jest src/trusted-contacts/trusted-contacts.service.spec.ts
```
Expected: PASS, 4 tests.

- [x] **Step 5: Add DTO, controller, and module**

`backend/src/trusted-contacts/dto/create-trusted-contact.dto.ts`:
```typescript
import { IsBoolean, IsIn, IsInt, IsString, Length, Min } from 'class-validator';

export const RELACOES = ['PSICOLOGO', 'PSIQUIATRA', 'T.O.', 'FAMILIAR', 'OUTRO'] as const;

export class CreateTrustedContactDto {
  @IsString()
  @Length(1, 100)
  nome: string;

  @IsIn(RELACOES)
  relacao: (typeof RELACOES)[number];

  @IsString()
  @Length(8, 20)
  whatsapp: string;

  @IsInt()
  @Min(0)
  prioridade: number;

  @IsBoolean()
  consentimentoAceito: boolean;
}
```

`backend/src/trusted-contacts/trusted-contacts.controller.ts`:
```typescript
import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { TrustedContactsService } from './trusted-contacts.service';
import { CreateTrustedContactDto } from './dto/create-trusted-contact.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('trusted-contacts')
export class TrustedContactsController {
  constructor(private readonly service: TrustedContactsService) {}

  @Post()
  async create(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: CreateTrustedContactDto) {
    return this.service.create(firebaseUid, dto);
  }

  @Get()
  async list(@CurrentFirebaseUid() firebaseUid: string) {
    return this.service.list(firebaseUid);
  }

  @Delete(':id')
  async remove(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    await this.service.remove(firebaseUid, id);
    return { success: true };
  }
}
```

`backend/src/trusted-contacts/trusted-contacts.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { TrustedContactsService } from './trusted-contacts.service';
import { TrustedContactsController } from './trusted-contacts.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [TrustedContactsService],
  controllers: [TrustedContactsController],
  exports: [TrustedContactsService],
})
export class TrustedContactsModule {}
```

- [x] **Step 6: Register the module in AppModule**

Modify `backend/src/app.module.ts` to add `TrustedContactsModule` to `imports`.

- [x] **Step 7: Commit**

```bash
git add backend/src/trusted-contacts backend/src/app.module.ts
git commit -m "feat: add trusted contacts module with mandatory consent"
```

---

### Task 7: Emergency message module

**Files:**
- Create: `backend/src/emergency/dto/build-emergency-message.dto.ts`
- Create: `backend/src/emergency/emergency.service.ts`
- Create: `backend/src/emergency/emergency.controller.ts`
- Create: `backend/src/emergency/emergency.module.ts`
- Test: `backend/src/emergency/emergency.service.spec.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Consumes: `UsersService.getByFirebaseUidOrThrow` (Task 4), `PrismaService` (Task 2), `TrustedContact` shape from Task 6 (`id`, `nome`, `whatsapp`, `userId`).
- Produces: `EmergencyService.buildMessage(firebaseUid: string, contactId: string): Promise<{ contactId, contactName, whatsapp, message, waUrl }>`. Route: `POST /emergency/message`.

- [x] **Step 1: Write the failing service test**

`backend/src/emergency/emergency.service.spec.ts`:
```typescript
import { NotFoundException } from '@nestjs/common';
import { EmergencyService } from './emergency.service';

describe('EmergencyService', () => {
  it('throws NotFoundException when the contact does not belong to the resolved user', async () => {
    const prisma = { trustedContact: { findFirst: jest.fn().mockResolvedValue(null) } };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new EmergencyService(prisma as any, usersService as any);

    await expect(service.buildMessage('fb1', 'c1')).rejects.toThrow(NotFoundException);
    expect(prisma.trustedContact.findFirst).toHaveBeenCalledWith({
      where: { id: 'c1', userId: 'u1' },
    });
  });

  it('builds a neutral pre-filled wa.me message using the contact first name', async () => {
    const prisma = {
      trustedContact: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'c1',
          nome: 'Marina Souza',
          whatsapp: '+55 11 99999-9999',
        }),
      },
    };
    const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
    const service = new EmergencyService(prisma as any, usersService as any);

    const result = await service.buildMessage('fb1', 'c1');

    expect(result.contactId).toBe('c1');
    expect(result.contactName).toBe('Marina Souza');
    expect(result.message).toBe(
      'Oi Marina, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.',
    );
    expect(result.waUrl).toBe(
      `https://wa.me/5511999999999?text=${encodeURIComponent(result.message)}`,
    );
  });
});
```

- [x] **Step 2: Run test to verify it fails**

```bash
npx jest src/emergency/emergency.service.spec.ts
```
Expected: FAIL — module not found.

- [x] **Step 3: Implement EmergencyService**

`backend/src/emergency/emergency.service.ts`:
```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';

@Injectable()
export class EmergencyService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
  ) {}

  async buildMessage(firebaseUid: string, contactId: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const contact = await this.prisma.trustedContact.findFirst({
      where: { id: contactId, userId: user.id },
    });

    if (!contact) {
      throw new NotFoundException('Contato não encontrado');
    }

    const primeiroNome = contact.nome.split(' ')[0];
    const mensagem = `Oi ${primeiroNome}, estou passando por um momento difícil agora e queria avisar. Não precisa ligar se não for possível.`;
    const numeroLimpo = contact.whatsapp.replace(/\D/g, '');
    const waUrl = `https://wa.me/${numeroLimpo}?text=${encodeURIComponent(mensagem)}`;

    return {
      contactId: contact.id,
      contactName: contact.nome,
      whatsapp: contact.whatsapp,
      message: mensagem,
      waUrl,
    };
  }
}
```

- [x] **Step 4: Run test to verify it passes**

```bash
npx jest src/emergency/emergency.service.spec.ts
```
Expected: PASS, 2 tests.

- [x] **Step 5: Add DTO, controller, and module**

`backend/src/emergency/dto/build-emergency-message.dto.ts`:
```typescript
import { IsUUID } from 'class-validator';

export class BuildEmergencyMessageDto {
  @IsUUID()
  contactId: string;
}
```

`backend/src/emergency/emergency.controller.ts`:
```typescript
import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { EmergencyService } from './emergency.service';
import { BuildEmergencyMessageDto } from './dto/build-emergency-message.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('emergency')
export class EmergencyController {
  constructor(private readonly service: EmergencyService) {}

  @Post('message')
  async buildMessage(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: BuildEmergencyMessageDto) {
    return this.service.buildMessage(firebaseUid, dto.contactId);
  }
}
```

`backend/src/emergency/emergency.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { EmergencyService } from './emergency.service';
import { EmergencyController } from './emergency.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [EmergencyService],
  controllers: [EmergencyController],
})
export class EmergencyModule {}
```

- [x] **Step 6: Register the module in AppModule**

Modify `backend/src/app.module.ts` to add `EmergencyModule` to `imports`. Final `imports` array should be:
```typescript
imports: [
  PrismaModule,
  AuthModule,
  UsersModule,
  SensoryProfileModule,
  TrustedContactsModule,
  EmergencyModule,
],
```

- [x] **Step 7: Commit**

```bash
git add backend/src/emergency backend/src/app.module.ts
git commit -m "feat: add emergency module to build pre-filled wa.me support messages"
```

---

### Task 8: End-to-end test for the full backend flow

**Files:**
- Create: `backend/test/onboarding-flow.e2e-spec.ts`
- Create: `backend/test/support/fake-firebase-admin.ts`

**Interfaces:**
- Consumes: `AppModule` (all modules from Tasks 1–7), `FIREBASE_ADMIN` token (Task 3).
- Produces: a repeatable e2e test proving the full chain: create user → set sensory profile → add trusted contact → build emergency message, all correctly scoped by `firebaseUid`.

- [x] **Step 1: Write the fake Firebase Admin test double**

`backend/test/support/fake-firebase-admin.ts`:
```typescript
export function buildFakeFirebaseAdmin() {
  return {
    auth: () => ({
      verifyIdToken: async (token: string) => {
        if (!token.startsWith('test-uid:')) {
          throw new Error('invalid test token');
        }
        return { uid: token.replace('test-uid:', '') };
      },
    }),
  };
}
```

- [x] **Step 2: Write the failing e2e test**

`backend/test/onboarding-flow.e2e-spec.ts`:
```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';

describe('Onboarding flow (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  const authHeader = { Authorization: 'Bearer test-uid:e2e-user-1' };

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
  });

  afterAll(async () => {
    await prisma.trustedContact.deleteMany({});
    await prisma.sensoryProfile.deleteMany({});
    await prisma.user.deleteMany({ where: { firebaseUid: 'e2e-user-1' } });
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
    expect(meAfterSignup.body.hasSensoryProfile).toBe(false);
    expect(meAfterSignup.body.trustedContactCount).toBe(0);

    await request(app.getHttpServer())
      .put('/sensory-profile')
      .set(authHeader)
      .send({ dados: { toleranciaNotificacao: 'SILENCIOSAS', gatilhos: ['Abrir o app do banco'] } })
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
    const contactId = contactResponse.body.id;

    const meAfterOnboarding = await request(app.getHttpServer())
      .get('/users/me')
      .set(authHeader)
      .expect(200);
    expect(meAfterOnboarding.body.hasSensoryProfile).toBe(true);
    expect(meAfterOnboarding.body.trustedContactCount).toBe(1);

    const emergencyResponse = await request(app.getHttpServer())
      .post('/emergency/message')
      .set(authHeader)
      .send({ contactId })
      .expect(201);

    expect(emergencyResponse.body.contactName).toBe('Dra. Marina');
    expect(emergencyResponse.body.waUrl).toContain('https://wa.me/5511999999999?text=');
  });

  it('rejects requests without a valid Firebase token', async () => {
    await request(app.getHttpServer()).get('/users/me').expect(401);
  });
});
```

- [x] **Step 3: Run test to verify it fails first (before Postgres is confirmed up)**

```bash
docker compose -f backend/docker-compose.yml up -d
cd backend && npx jest --config ./test/jest-e2e.json onboarding-flow
```
If `jest-e2e.json` does not exist yet (default Nest scaffold names it `test/jest-e2e.json`), verify it points `rootDir` at `..` and `testRegex` at `.e2e-spec.ts$`. Expected on first run before Task 1–7 code exists: FAIL. Since Tasks 1–7 are already implemented at this point, expected result here is actually a real run — if it fails, read the error and fix any drift between this test and the actual DTOs/routes before proceeding.

- [x] **Step 4: Run test to verify it passes**

```bash
cd backend && npx jest --config ./test/jest-e2e.json onboarding-flow
```
Expected: PASS, 2 tests.

- [x] **Step 5: Commit**

```bash
git add backend/test
git commit -m "test: add e2e coverage for the full onboarding, anamnese, and emergency flow"
```

---

## Mobile (Flutter)

### Task 9: Flutter project scaffold + Firebase Auth (email/password)

**Files:**
- Create: `mobile/` (via `flutter create`)
- Create: `mobile/lib/main.dart`
- Create: `mobile/lib/features/auth/auth_service.dart`
- Create: `mobile/lib/features/auth/signup_screen.dart`
- Create: `mobile/lib/features/auth/login_screen.dart`
- Test: `mobile/test/features/auth/auth_service_test.dart`

**Interfaces:**
- Produces: `AuthService` with `signUp(email, password): Future<User>`, `logIn(email, password): Future<User>`, `currentUser: User?`, `authStateChanges(): Stream<User?>`. Screens routed to from `main.dart`.

- [x] **Step 1: Scaffold the Flutter project**

```bash
flutter create --org com.sincro --project-name sincro_mobile mobile
cd mobile
flutter pub add firebase_core firebase_auth flutter_riverpod dio url_launcher
flutter pub add -d mocktail
```

- [x] **Step 2: Configure Firebase for the project**

Run `flutterfire configure` (requires the Firebase CLI logged in and a Firebase project already created in the console) to generate `mobile/lib/firebase_options.dart`. This step requires interactive CLI selection of the Firebase project and platforms (iOS/Android) — run it manually and confirm `firebase_options.dart` was generated before continuing.

- [x] **Step 3: Write the failing AuthService test**

`mobile/test/features/auth/auth_service_test.dart`:
```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/features/auth/auth_service.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

void main() {
  late MockFirebaseAuth mockFirebaseAuth;
  late AuthService authService;

  setUp(() {
    mockFirebaseAuth = MockFirebaseAuth();
    authService = AuthService(mockFirebaseAuth);
  });

  test('signUp delegates to createUserWithEmailAndPassword and returns the user', () async {
    final mockUser = MockUser();
    final mockCredential = MockUserCredential();
    when(() => mockCredential.user).thenReturn(mockUser);
    when(
      () => mockFirebaseAuth.createUserWithEmailAndPassword(
        email: 'ana@example.com',
        password: 'senha-forte-123',
      ),
    ).thenAnswer((_) async => mockCredential);

    final result = await authService.signUp('ana@example.com', 'senha-forte-123');

    expect(result, mockUser);
  });

  test('logIn delegates to signInWithEmailAndPassword and returns the user', () async {
    final mockUser = MockUser();
    final mockCredential = MockUserCredential();
    when(() => mockCredential.user).thenReturn(mockUser);
    when(
      () => mockFirebaseAuth.signInWithEmailAndPassword(
        email: 'ana@example.com',
        password: 'senha-forte-123',
      ),
    ).thenAnswer((_) async => mockCredential);

    final result = await authService.logIn('ana@example.com', 'senha-forte-123');

    expect(result, mockUser);
  });
}
```

- [x] **Step 4: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/auth/auth_service_test.dart
```
Expected: FAIL — `Target of URI doesn't exist: 'package:sincro_mobile/features/auth/auth_service.dart'`.

- [x] **Step 5: Implement AuthService**

`mobile/lib/features/auth/auth_service.dart`:
```dart
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService(this._firebaseAuth);

  final FirebaseAuth _firebaseAuth;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  Future<User?> signUp(String email, String password) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return credential.user;
  }

  Future<User?> logIn(String email, String password) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return credential.user;
  }

  Future<void> signOut() => _firebaseAuth.signOut();
}
```

- [x] **Step 6: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/auth/auth_service_test.dart
```
Expected: PASS, 2 tests.

- [x] **Step 7: Build the signup and login screens**

`mobile/lib/features/auth/signup_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_providers.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = ref.read(authServiceProvider);
      await authService.signUp(_emailController.text.trim(), _senhaController.text);
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/onboarding', arguments: _nomeController.text.trim());
      }
    } catch (e) {
      setState(() => _error = 'Não foi possível criar sua conta. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Seu nome'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'E-mail'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _senhaController,
              decoration: const InputDecoration(labelText: 'Senha'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading ? const CircularProgressIndicator() : const Text('Criar conta'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`mobile/lib/features/auth/login_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authService = ref.read(authServiceProvider);
      await authService.logIn(_emailController.text.trim(), _senhaController.text);
      if (mounted) Navigator.of(context).pushReplacementNamed('/onboarding-router');
    } catch (e) {
      setState(() => _error = 'E-mail ou senha inválidos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'E-mail'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _senhaController,
              decoration: const InputDecoration(labelText: 'Senha'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading ? const CircularProgressIndicator() : const Text('Entrar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamed('/signup'),
              child: const Text('Criar uma conta'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`mobile/lib/features/auth/auth_providers.dart`:
```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseAuthProvider));
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});
```

- [x] **Step 8: Wire up `main.dart`**

`mobile/lib/main.dart`:
```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: SincroApp()));
}

class SincroApp extends StatelessWidget {
  const SincroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sincro',
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
      },
    );
  }
}
```

- [x] **Step 9: Commit**

```bash
git add mobile
git commit -m "feat: scaffold Flutter app with Firebase email/password auth"
```

---

### Task 10: API client with Firebase token interceptor

**Files:**
- Create: `mobile/lib/core/api_client.dart`
- Create: `mobile/lib/core/api_providers.dart`
- Test: `mobile/test/core/api_client_test.dart`

**Interfaces:**
- Consumes: `FirebaseAuth` (Task 9, via `firebase_auth` package directly).
- Produces: `ApiClient` with `dio` (Dio instance) attaching `Authorization: Bearer <idToken>` to every request when a user is signed in. `apiClientProvider` (Riverpod `Provider<ApiClient>`) consumed by Tasks 11–14.

- [x] **Step 1: Write the failing test**

`mobile/test/core/api_client_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/core/api_client.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

void main() {
  test('attaches the Firebase ID token as a bearer header when a user is signed in', () async {
    final mockAuth = MockFirebaseAuth();
    final mockUser = MockUser();
    when(() => mockUser.getIdToken()).thenAnswer((_) async => 'fake-id-token');
    when(() => mockAuth.currentUser).thenReturn(mockUser);

    final apiClient = ApiClient(baseUrl: 'http://localhost:3000', firebaseAuth: mockAuth);
    final options = RequestOptions(path: '/users/me');
    final handler = RequestInterceptorHandler();

    apiClient.dio.interceptors.first.onRequest(options, handler);
    await Future<void>.delayed(Duration.zero);

    expect(options.headers['Authorization'], 'Bearer fake-id-token');
  });

  test('does not attach an Authorization header when no user is signed in', () async {
    final mockAuth = MockFirebaseAuth();
    when(() => mockAuth.currentUser).thenReturn(null);

    final apiClient = ApiClient(baseUrl: 'http://localhost:3000', firebaseAuth: mockAuth);
    final options = RequestOptions(path: '/users/me');
    final handler = RequestInterceptorHandler();

    apiClient.dio.interceptors.first.onRequest(options, handler);
    await Future<void>.delayed(Duration.zero);

    expect(options.headers.containsKey('Authorization'), isFalse);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/core/api_client_test.dart
```
Expected: FAIL — module not found.

- [x] **Step 3: Implement ApiClient**

`mobile/lib/core/api_client.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApiClient {
  ApiClient({required this.baseUrl, required FirebaseAuth firebaseAuth})
      : _firebaseAuth = firebaseAuth {
    dio = Dio(BaseOptions(baseUrl: baseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final user = _firebaseAuth.currentUser;
          if (user != null) {
            final token = await user.getIdToken();
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final String baseUrl;
  final FirebaseAuth _firebaseAuth;
  late final Dio dio;
}
```

- [x] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/core/api_client_test.dart
```
Expected: PASS, 2 tests.

- [x] **Step 5: Add the Riverpod provider**

`mobile/lib/core/api_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/auth_providers.dart';
import 'api_client.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: apiBaseUrl, firebaseAuth: ref.watch(firebaseAuthProvider));
});
```

- [x] **Step 6: Commit**

```bash
git add mobile/lib/core mobile/test/core
git commit -m "feat: add API client with Firebase token interceptor"
```

---

### Task 11: Onboarding status repository and router

**Files:**
- Create: `mobile/lib/features/onboarding/onboarding_status.dart`
- Create: `mobile/lib/features/onboarding/users_repository.dart`
- Create: `mobile/lib/features/onboarding/onboarding_router.dart`
- Test: `mobile/test/features/onboarding/users_repository_test.dart`

**Interfaces:**
- Consumes: `ApiClient` (Task 10).
- Produces: `OnboardingStatus` model, `UsersRepository.upsertMe(nome): Future<void>`, `UsersRepository.getMe(): Future<OnboardingStatus>`. `OnboardingRouterScreen` widget that reads status and navigates to `/onboarding/anamnese`, `/onboarding/contacts`, or `/home` — consumed by Task 9's login flow and Tasks 12–14's screens.

- [x] **Step 1: Write the failing repository test**

`mobile/test/features/onboarding/users_repository_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/onboarding/users_repository.dart';

void main() {
  test('getMe parses the onboarding status response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter();
    final repository = UsersRepository(dio);

    final status = await repository.getMe();

    expect(status.userId, 'u1');
    expect(status.nome, 'Ana');
    expect(status.hasSensoryProfile, true);
    expect(status.trustedContactCount, 2);
  });
}

class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = '{"userId":"u1","nome":"Ana","hasSensoryProfile":true,"trustedContactCount":2}';
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/onboarding/users_repository_test.dart
```
Expected: FAIL — module not found.

- [x] **Step 3: Implement the model and repository**

`mobile/lib/features/onboarding/onboarding_status.dart`:
```dart
class OnboardingStatus {
  const OnboardingStatus({
    required this.userId,
    required this.nome,
    required this.hasSensoryProfile,
    required this.trustedContactCount,
  });

  final String userId;
  final String nome;
  final bool hasSensoryProfile;
  final int trustedContactCount;

  factory OnboardingStatus.fromJson(Map<String, dynamic> json) {
    return OnboardingStatus(
      userId: json['userId'] as String,
      nome: json['nome'] as String,
      hasSensoryProfile: json['hasSensoryProfile'] as bool,
      trustedContactCount: json['trustedContactCount'] as int,
    );
  }
}
```

`mobile/lib/features/onboarding/users_repository.dart`:
```dart
import 'package:dio/dio.dart';
import 'onboarding_status.dart';

class UsersRepository {
  UsersRepository(this._dio);

  final Dio _dio;

  Future<void> upsertMe(String nome) async {
    await _dio.post('/users/me', data: {'nome': nome});
  }

  Future<OnboardingStatus> getMe() async {
    final response = await _dio.get('/users/me');
    return OnboardingStatus.fromJson(response.data as Map<String, dynamic>);
  }
}
```

- [x] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/onboarding/users_repository_test.dart
```
Expected: PASS, 1 test.

- [x] **Step 5: Add the provider and router screen**

`mobile/lib/features/onboarding/onboarding_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'users_repository.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(ref.watch(apiClientProvider).dio);
});
```

`mobile/lib/features/onboarding/onboarding_router.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'onboarding_providers.dart';

class OnboardingRouterScreen extends ConsumerWidget {
  const OnboardingRouterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersRepository = ref.watch(usersRepositoryProvider);

    return FutureBuilder(
      future: usersRepository.getMe(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return const Scaffold(body: Center(child: Text('Não foi possível carregar seu perfil.')));
        }
        final status = snapshot.data!;
        if (!status.hasSensoryProfile) {
          return const _RedirectOnce(routeName: '/onboarding/anamnese');
        }
        if (status.trustedContactCount == 0) {
          return const _RedirectOnce(routeName: '/onboarding/contacts');
        }
        return const _RedirectOnce(routeName: '/home');
      },
    );
  }
}

class _RedirectOnce extends StatefulWidget {
  const _RedirectOnce({required this.routeName});

  final String routeName;

  @override
  State<_RedirectOnce> createState() => _RedirectOnceState();
}

class _RedirectOnceState extends State<_RedirectOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed(widget.routeName);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
```

- [x] **Step 6: Register the `/onboarding-router` route in `main.dart`**

Modify `mobile/lib/main.dart` to add the import and route:
```dart
import 'features/onboarding/onboarding_router.dart';
// ...
routes: {
  '/login': (_) => const LoginScreen(),
  '/signup': (_) => const SignupScreen(),
  '/onboarding-router': (_) => const OnboardingRouterScreen(),
},
```

- [x] **Step 7: Commit**

```bash
git add mobile/lib/features/onboarding mobile/lib/main.dart mobile/test/features/onboarding
git commit -m "feat: add onboarding status repository and routing screen"
```

---

### Task 12: Anamnese wizard

**Files:**
- Create: `mobile/lib/features/onboarding/anamnese/anamnese_answers.dart`
- Create: `mobile/lib/features/onboarding/anamnese/anamnese_notifier.dart`
- Create: `mobile/lib/features/onboarding/anamnese/anamnese_wizard_screen.dart`
- Test: `mobile/test/features/onboarding/anamnese/anamnese_notifier_test.dart`

**Interfaces:**
- Consumes: `SensoryProfileRepository` (created in this task, mirroring `UsersRepository`'s pattern from Task 11), `apiClientProvider` (Task 10).
- Produces: `AnamneseAnswers` model, `AnamneseNotifier` (Riverpod `StateNotifier<AnamneseAnswers>`) with `setTolerancia`, `toggleGatilho`, `setTom`, and `submit(): Future<void>`. Route `/onboarding/anamnese` registered in `main.dart`, navigating to `/onboarding/contacts` (Task 13) on success.

- [x] **Step 1: Write the failing notifier test**

`mobile/test/features/onboarding/anamnese/anamnese_notifier_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/anamnese_notifier.dart';

class _FakeSensoryProfileRepository {
  Map<String, dynamic>? lastSubmittedDados;

  Future<void> upsert(Map<String, dynamic> dados) async {
    lastSubmittedDados = dados;
  }
}

void main() {
  test('toggling a gatilho adds and removes it', () {
    final notifier = AnamneseNotifier(_FakeSensoryProfileRepository() as dynamic);

    notifier.toggleGatilho('Abrir o app do banco');
    expect(notifier.state.gatilhos, contains('Abrir o app do banco'));

    notifier.toggleGatilho('Abrir o app do banco');
    expect(notifier.state.gatilhos, isNot(contains('Abrir o app do banco')));
  });

  test('submit sends the current answers as dados', () async {
    final fakeRepo = _FakeSensoryProfileRepository();
    final notifier = AnamneseNotifier(fakeRepo as dynamic);

    notifier.setTolerancia('SILENCIOSAS');
    notifier.toggleGatilho('Ligações não agendadas');
    notifier.setTom('DIRETO_E_CURTO');
    await notifier.submit();

    expect(fakeRepo.lastSubmittedDados, {
      'toleranciaNotificacao': 'SILENCIOSAS',
      'gatilhos': ['Ligações não agendadas'],
      'tomPreferido': 'DIRETO_E_CURTO',
    });
  });
}
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/onboarding/anamnese/anamnese_notifier_test.dart
```
Expected: FAIL — module not found.

- [x] **Step 3: Implement the answers model and repository**

`mobile/lib/features/onboarding/anamnese/anamnese_answers.dart`:
```dart
class AnamneseAnswers {
  const AnamneseAnswers({
    this.toleranciaNotificacao,
    this.gatilhos = const [],
    this.tomPreferido,
  });

  final String? toleranciaNotificacao;
  final List<String> gatilhos;
  final String? tomPreferido;

  AnamneseAnswers copyWith({
    String? toleranciaNotificacao,
    List<String>? gatilhos,
    String? tomPreferido,
  }) {
    return AnamneseAnswers(
      toleranciaNotificacao: toleranciaNotificacao ?? this.toleranciaNotificacao,
      gatilhos: gatilhos ?? this.gatilhos,
      tomPreferido: tomPreferido ?? this.tomPreferido,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'toleranciaNotificacao': toleranciaNotificacao,
      'gatilhos': gatilhos,
      'tomPreferido': tomPreferido,
    };
  }
}
```

`mobile/lib/features/onboarding/anamnese/sensory_profile_repository.dart`:
```dart
import 'package:dio/dio.dart';

class SensoryProfileRepository {
  SensoryProfileRepository(this._dio);

  final Dio _dio;

  Future<void> upsert(Map<String, dynamic> dados) async {
    await _dio.put('/sensory-profile', data: {'dados': dados});
  }
}
```

- [x] **Step 4: Implement AnamneseNotifier**

`mobile/lib/features/onboarding/anamnese/anamnese_notifier.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'anamnese_answers.dart';
import 'sensory_profile_repository.dart';

class AnamneseNotifier extends StateNotifier<AnamneseAnswers> {
  AnamneseNotifier(this._repository) : super(const AnamneseAnswers());

  final SensoryProfileRepository _repository;

  void setTolerancia(String value) {
    state = state.copyWith(toleranciaNotificacao: value);
  }

  void toggleGatilho(String gatilho) {
    final gatilhos = List<String>.from(state.gatilhos);
    if (gatilhos.contains(gatilho)) {
      gatilhos.remove(gatilho);
    } else {
      gatilhos.add(gatilho);
    }
    state = state.copyWith(gatilhos: gatilhos);
  }

  void setTom(String value) {
    state = state.copyWith(tomPreferido: value);
  }

  Future<void> submit() async {
    await _repository.upsert(state.toJson());
  }
}
```

- [x] **Step 5: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/onboarding/anamnese/anamnese_notifier_test.dart
```
Expected: PASS, 2 tests.

- [x] **Step 6: Build the wizard screen (4 steps in a `PageView`)**

`mobile/lib/features/onboarding/anamnese/anamnese_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api_providers.dart';
import 'anamnese_answers.dart';
import 'anamnese_notifier.dart';
import 'sensory_profile_repository.dart';

final sensoryProfileRepositoryProvider = Provider<SensoryProfileRepository>((ref) {
  return SensoryProfileRepository(ref.watch(apiClientProvider).dio);
});

final anamneseNotifierProvider = StateNotifierProvider<AnamneseNotifier, AnamneseAnswers>((ref) {
  return AnamneseNotifier(ref.watch(sensoryProfileRepositoryProvider));
});
```

`mobile/lib/features/onboarding/anamnese/anamnese_wizard_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'anamnese_providers.dart';

const _gatilhosDisponiveis = [
  'Abrir o app do banco',
  'Ligações não agendadas',
  'Mudança de última hora na agenda',
  'Ambientes barulhentos',
];

class AnamneseWizardScreen extends ConsumerStatefulWidget {
  const AnamneseWizardScreen({super.key});

  @override
  ConsumerState<AnamneseWizardScreen> createState() => _AnamneseWizardScreenState();
}

class _AnamneseWizardScreenState extends ConsumerState<AnamneseWizardScreen> {
  final _pageController = PageController();
  int _step = 0;
  bool _submitting = false;

  void _goToStep(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(step, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
  }

  Future<void> _finish() async {
    setState(() => _submitting = true);
    await ref.read(anamneseNotifierProvider.notifier).submit();
    if (mounted) Navigator.of(context).pushReplacementNamed('/onboarding/contacts');
  }

  @override
  Widget build(BuildContext context) {
    final answers = ref.watch(anamneseNotifierProvider);
    final notifier = ref.read(anamneseNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text('Sobre você (${_step + 1}/4)')),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _NotificationStep(
            selected: answers.toleranciaNotificacao,
            onSelect: (value) {
              notifier.setTolerancia(value);
              _goToStep(1);
            },
          ),
          _TriggersStep(
            selected: answers.gatilhos,
            onToggle: notifier.toggleGatilho,
            onNext: () => _goToStep(2),
          ),
          _ToneStep(
            selected: answers.tomPreferido,
            onSelect: (value) {
              notifier.setTom(value);
              _goToStep(3);
            },
          ),
          _SummaryStep(
            answers: answers,
            onEditStep: _goToStep,
            onConfirm: _submitting ? null : _finish,
          ),
        ],
      ),
    );
  }
}

class _NotificationStep extends StatelessWidget {
  const _NotificationStep({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Como você prefere receber notificações?',
      children: [
        _ChoiceButton(label: 'Silenciosas', value: 'SILENCIOSAS', groupValue: selected, onSelect: onSelect),
        _ChoiceButton(label: 'Só em horários específicos', value: 'HORARIOS_ESPECIFICOS', groupValue: selected, onSelect: onSelect),
        _ChoiceButton(label: 'Padrão', value: 'PADRAO', groupValue: selected, onSelect: onSelect),
      ],
    );
  }
}

class _TriggersStep extends StatelessWidget {
  const _TriggersStep({required this.selected, required this.onToggle, required this.onNext});

  final List<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Algum desses costuma te incomodar?',
      children: [
        Wrap(
          spacing: 8,
          children: _gatilhosDisponiveis.map((gatilho) {
            return FilterChip(
              label: Text(gatilho),
              selected: selected.contains(gatilho),
              onSelected: (_) => onToggle(gatilho),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: onNext, child: const Text('Continuar')),
      ],
    );
  }
}

class _ToneStep extends StatelessWidget {
  const _ToneStep({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Como você prefere que as mensagens sejam escritas?',
      children: [
        _ChoiceButton(label: 'Direto e curto', value: 'DIRETO_E_CURTO', groupValue: selected, onSelect: onSelect),
        _ChoiceButton(label: 'Levemente mais explicativo', value: 'EXPLICATIVO', groupValue: selected, onSelect: onSelect),
      ],
    );
  }
}

class _SummaryStep extends StatelessWidget {
  const _SummaryStep({required this.answers, required this.onEditStep, required this.onConfirm});

  final dynamic answers;
  final ValueChanged<int> onEditStep;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Confirme suas respostas',
      children: [
        ListTile(
          title: const Text('Notificações'),
          subtitle: Text(answers.toleranciaNotificacao ?? '—'),
          trailing: TextButton(onPressed: () => onEditStep(0), child: const Text('Editar')),
        ),
        ListTile(
          title: const Text('Gatilhos'),
          subtitle: Text(answers.gatilhos.isEmpty ? 'Nenhum' : answers.gatilhos.join(', ')),
          trailing: TextButton(onPressed: () => onEditStep(1), child: const Text('Editar')),
        ),
        ListTile(
          title: const Text('Tom preferido'),
          subtitle: Text(answers.tomPreferido ?? '—'),
          trailing: TextButton(onPressed: () => onEditStep(2), child: const Text('Editar')),
        ),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: onConfirm, child: const Text('Confirmar')),
      ],
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onSelect,
  });

  final String label;
  final String value;
  final String? groupValue;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = groupValue == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
        onPressed: () => onSelect(value),
        child: Text(label),
      ),
    );
  }
}
```

- [x] **Step 7: Register the `/onboarding/anamnese` route**

Modify `mobile/lib/main.dart` to add the import and route entry:
```dart
import 'features/onboarding/anamnese/anamnese_wizard_screen.dart';
// ...
'/onboarding/anamnese': (_) => const AnamneseWizardScreen(),
```

- [x] **Step 8: Commit**

```bash
git add mobile/lib/features/onboarding/anamnese mobile/lib/main.dart mobile/test/features/onboarding/anamnese
git commit -m "feat: add anamnese wizard with notification, triggers, tone, and summary steps"
```

---

### Task 13: Trusted contacts screens

**Files:**
- Create: `mobile/lib/features/trusted_contacts/trusted_contact.dart`
- Create: `mobile/lib/features/trusted_contacts/trusted_contacts_repository.dart`
- Create: `mobile/lib/features/trusted_contacts/trusted_contacts_providers.dart`
- Create: `mobile/lib/features/trusted_contacts/trusted_contacts_screen.dart`
- Create: `mobile/lib/features/trusted_contacts/add_contact_screen.dart`
- Test: `mobile/test/features/trusted_contacts/trusted_contacts_repository_test.dart`

**Interfaces:**
- Consumes: `apiClientProvider` (Task 10).
- Produces: `TrustedContact` model, `TrustedContactsRepository.list()`, `.create(...)`, `.remove(id)`. Routes `/onboarding/contacts` and `/onboarding/contacts/add`, navigating to `/home` (Task 14) once at least one contact exists.

- [x] **Step 1: Write the failing repository test**

`mobile/test/features/trusted_contacts/trusted_contacts_repository_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_repository.dart';

void main() {
  test('create posts the contact payload including consent', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedData;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data as Map<String, dynamic>;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'id': 'c1'}));
    }));
    final repository = TrustedContactsRepository(dio);

    await repository.create(
      nome: 'Dra. Marina',
      relacao: 'PSICOLOGO',
      whatsapp: '+5511999999999',
      prioridade: 0,
      consentimentoAceito: true,
    );

    expect(capturedData, {
      'nome': 'Dra. Marina',
      'relacao': 'PSICOLOGO',
      'whatsapp': '+5511999999999',
      'prioridade': 0,
      'consentimentoAceito': true,
    });
  });
}
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/trusted_contacts/trusted_contacts_repository_test.dart
```
Expected: FAIL — module not found.

- [x] **Step 3: Implement the model and repository**

`mobile/lib/features/trusted_contacts/trusted_contact.dart`:
```dart
class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.nome,
    required this.relacao,
    required this.whatsapp,
    required this.prioridade,
  });

  final String id;
  final String nome;
  final String relacao;
  final String whatsapp;
  final int prioridade;

  factory TrustedContact.fromJson(Map<String, dynamic> json) {
    return TrustedContact(
      id: json['id'] as String,
      nome: json['nome'] as String,
      relacao: json['relacao'] as String,
      whatsapp: json['whatsapp'] as String,
      prioridade: json['prioridade'] as int,
    );
  }
}
```

`mobile/lib/features/trusted_contacts/trusted_contacts_repository.dart`:
```dart
import 'package:dio/dio.dart';
import 'trusted_contact.dart';

class TrustedContactsRepository {
  TrustedContactsRepository(this._dio);

  final Dio _dio;

  Future<List<TrustedContact>> list() async {
    final response = await _dio.get('/trusted-contacts');
    return (response.data as List)
        .map((json) => TrustedContact.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> create({
    required String nome,
    required String relacao,
    required String whatsapp,
    required int prioridade,
    required bool consentimentoAceito,
  }) async {
    await _dio.post('/trusted-contacts', data: {
      'nome': nome,
      'relacao': relacao,
      'whatsapp': whatsapp,
      'prioridade': prioridade,
      'consentimentoAceito': consentimentoAceito,
    });
  }

  Future<void> remove(String id) async {
    await _dio.delete('/trusted-contacts/$id');
  }
}
```

- [x] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/trusted_contacts/trusted_contacts_repository_test.dart
```
Expected: PASS, 1 test.

- [x] **Step 5: Add providers and screens**

`mobile/lib/features/trusted_contacts/trusted_contacts_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'trusted_contact.dart';
import 'trusted_contacts_repository.dart';

final trustedContactsRepositoryProvider = Provider<TrustedContactsRepository>((ref) {
  return TrustedContactsRepository(ref.watch(apiClientProvider).dio);
});

final trustedContactsListProvider = FutureProvider.autoDispose<List<TrustedContact>>((ref) {
  return ref.watch(trustedContactsRepositoryProvider).list();
});
```

`mobile/lib/features/trusted_contacts/add_contact_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'trusted_contacts_providers.dart';

const _relacoes = ['PSICOLOGO', 'PSIQUIATRA', 'T.O.', 'FAMILIAR', 'OUTRO'];

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _nomeController = TextEditingController();
  final _whatsappController = TextEditingController();
  String _relacao = _relacoes.first;
  bool _consentimentoAceito = false;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final repository = ref.read(trustedContactsRepositoryProvider);
    await repository.create(
      nome: _nomeController.text.trim(),
      relacao: _relacao,
      whatsapp: _whatsappController.text.trim(),
      prioridade: 0,
      consentimentoAceito: _consentimentoAceito,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nomeController.text.trim().isNotEmpty &&
        _whatsappController.text.trim().isNotEmpty &&
        _consentimentoAceito &&
        !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar contato de confiança')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _relacao,
              items: _relacoes.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (value) => setState(() => _relacao = value!),
              decoration: const InputDecoration(labelText: 'Relação'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _whatsappController,
              decoration: const InputDecoration(labelText: 'WhatsApp'),
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _consentimentoAceito,
              onChanged: (value) => setState(() => _consentimentoAceito = value ?? false),
              title: const Text(
                'Você autoriza o Sincro a preparar mensagens de alerta para este contato em momentos de crise. Você sempre confirma antes do envio.',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: canSave ? _save : null,
              child: _saving ? const CircularProgressIndicator() : const Text('Salvar contato'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`mobile/lib/features/trusted_contacts/trusted_contacts_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'add_contact_screen.dart';
import 'trusted_contacts_providers.dart';

class TrustedContactsScreen extends ConsumerWidget {
  const TrustedContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(trustedContactsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rede de apoio')),
      body: contactsAsync.when(
        data: (contacts) {
          if (contacts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Cadastre ao menos um contato de confiança para continuar.'),
              ),
            );
          }
          return ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return ListTile(title: Text(contact.nome), subtitle: Text(contact.relacao));
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível carregar seus contatos.')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Adicionar contato'),
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AddContactScreen()),
          );
          if (added == true) {
            ref.invalidate(trustedContactsListProvider);
          }
        },
      ),
      bottomNavigationBar: contactsAsync.maybeWhen(
        data: (contacts) => contacts.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
                  child: const Text('Continuar'),
                ),
              )
            : null,
        orElse: () => null,
      ),
    );
  }
}
```

- [x] **Step 6: Register the routes**

Modify `mobile/lib/main.dart`:
```dart
import 'features/trusted_contacts/trusted_contacts_screen.dart';
// ...
'/onboarding/contacts': (_) => const TrustedContactsScreen(),
```

- [x] **Step 7: Commit**

```bash
git add mobile/lib/features/trusted_contacts mobile/lib/main.dart mobile/test/features/trusted_contacts
git commit -m "feat: add trusted contacts list, add-contact form, and mandatory consent checkbox"
```

---

### Task 14: Home screen and emergency flow

**Files:**
- Create: `mobile/lib/features/emergency/emergency_message.dart`
- Create: `mobile/lib/features/emergency/emergency_repository.dart`
- Create: `mobile/lib/features/emergency/emergency_providers.dart`
- Create: `mobile/lib/features/home/home_screen.dart`
- Create: `mobile/lib/features/home/emergency_button.dart`
- Test: `mobile/test/features/emergency/emergency_repository_test.dart`

**Interfaces:**
- Consumes: `apiClientProvider` (Task 10), `TrustedContactsRepository`/`trustedContactsListProvider` (Task 13).
- Produces: `EmergencyMessage` model, `EmergencyRepository.buildMessage(contactId): Future<EmergencyMessage>`. `HomeScreen` (route `/home`) with the "Avisar Rede de Apoio" button that opens the resulting `waUrl` via `url_launcher`.

- [x] **Step 1: Write the failing repository test**

`mobile/test/features/emergency/emergency_repository_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/emergency/emergency_repository.dart';

void main() {
  test('buildMessage posts the contactId and parses the response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {
          'contactId': 'c1',
          'contactName': 'Dra. Marina',
          'whatsapp': '+5511999999999',
          'message': 'Oi Marina, estou passando por um momento difícil agora.',
          'waUrl': 'https://wa.me/5511999999999?text=teste',
        },
      ));
    }));
    final repository = EmergencyRepository(dio);

    final result = await repository.buildMessage('c1');

    expect(result.contactName, 'Dra. Marina');
    expect(result.waUrl, 'https://wa.me/5511999999999?text=teste');
  });
}
```

- [x] **Step 2: Run test to verify it fails**

```bash
cd mobile && flutter test test/features/emergency/emergency_repository_test.dart
```
Expected: FAIL — module not found.

- [x] **Step 3: Implement the model and repository**

`mobile/lib/features/emergency/emergency_message.dart`:
```dart
class EmergencyMessage {
  const EmergencyMessage({
    required this.contactId,
    required this.contactName,
    required this.whatsapp,
    required this.message,
    required this.waUrl,
  });

  final String contactId;
  final String contactName;
  final String whatsapp;
  final String message;
  final String waUrl;

  factory EmergencyMessage.fromJson(Map<String, dynamic> json) {
    return EmergencyMessage(
      contactId: json['contactId'] as String,
      contactName: json['contactName'] as String,
      whatsapp: json['whatsapp'] as String,
      message: json['message'] as String,
      waUrl: json['waUrl'] as String,
    );
  }
}
```

`mobile/lib/features/emergency/emergency_repository.dart`:
```dart
import 'package:dio/dio.dart';
import 'emergency_message.dart';

class EmergencyRepository {
  EmergencyRepository(this._dio);

  final Dio _dio;

  Future<EmergencyMessage> buildMessage(String contactId) async {
    final response = await _dio.post('/emergency/message', data: {'contactId': contactId});
    return EmergencyMessage.fromJson(response.data as Map<String, dynamic>);
  }
}
```

- [x] **Step 4: Run test to verify it passes**

```bash
cd mobile && flutter test test/features/emergency/emergency_repository_test.dart
```
Expected: PASS, 1 test.

- [x] **Step 5: Add the provider, emergency button, and home screen**

`mobile/lib/features/emergency/emergency_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'emergency_repository.dart';

final emergencyRepositoryProvider = Provider<EmergencyRepository>((ref) {
  return EmergencyRepository(ref.watch(apiClientProvider).dio);
});
```

`mobile/lib/features/home/emergency_button.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../emergency/emergency_providers.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';

class EmergencyButton extends ConsumerWidget {
  const EmergencyButton({super.key});

  Future<void> _handlePress(BuildContext context, WidgetRef ref) async {
    final contacts = await ref.read(trustedContactsRepositoryProvider).list();
    if (contacts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cadastre um contato de confiança primeiro.')),
        );
      }
      return;
    }

    final priorityContact = contacts.first;
    final message = await ref.read(emergencyRepositoryProvider).buildMessage(priorityContact.id);

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Avisar ${message.contactName}?'),
        content: Text(message.message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Agora não')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Abrir WhatsApp')),
        ],
      ),
    );

    if (confirmed == true) {
      await launchUrl(Uri.parse(message.waUrl), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      onPressed: () => _handlePress(context, ref),
      icon: const Icon(Icons.favorite),
      label: const Text('Avisar Rede de Apoio'),
    );
  }
}
```

`mobile/lib/features/home/home_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'emergency_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sincro')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            Text('🌿 Tudo em ordem por hoje.'),
            SizedBox(height: 8),
            Text('Finanças e e-mails chegam em breve.'),
            SizedBox(height: 32),
            EmergencyButton(),
          ],
        ),
      ),
    );
  }
}
```

- [x] **Step 6: Register the `/home` route**

Modify `mobile/lib/main.dart`:
```dart
import 'features/home/home_screen.dart';
// ...
'/home': (_) => const HomeScreen(),
```

- [x] **Step 7: Commit**

```bash
git add mobile/lib/features/emergency mobile/lib/features/home mobile/lib/main.dart mobile/test/features/emergency
git commit -m "feat: add home screen with emergency wa.me handoff flow"
```

---

### Task 15: Post-onboarding profile & contacts management (added post-final-review)

**Status: ✅ Done** (commits `b3ea0f5..f0c32dd`, one fix round — edit mode initially opened a blank wizard instead of loading the saved profile; fixed by adding `SensoryProfileRepository.get()` + `AnamneseAnswers.fromJson` + seeding the notifier before the wizard renders).

**Why:** The design spec's objective 5 ("Edite ou apague seu perfil sensorial e seus contatos a qualquer momento") and its "Direito de exclusão" LGPD requirement (`docs/superpowers/specs/2026-08-01-onboarding-anamnese-rede-apoio-design.md` line 25, line 166-167) were never assigned to any of Tasks 1-14. The final whole-branch review caught this: `/home` has no outgoing navigation at all, `TrustedContactsRepository.remove()` and the backend's `DELETE /trusted-contacts/:id` are dead code with no caller, `AuthService.signOut()` is dead code, and there is no delete endpoint for the sensory profile at all.

**Files:**
- Create: `backend/src/sensory-profile/dto/` — no new DTO needed (delete has no body)
- Modify: `backend/src/sensory-profile/sensory-profile.service.ts` (add `remove(firebaseUid): Promise<void>`)
- Modify: `backend/src/sensory-profile/sensory-profile.controller.ts` (add `@Delete()` route)
- Modify/Test: `backend/src/sensory-profile/sensory-profile.service.spec.ts`
- Modify: `mobile/lib/features/onboarding/anamnese/sensory_profile_repository.dart` (add `remove(): Future<void>` calling `DELETE /sensory-profile`)
- Modify: `mobile/lib/features/onboarding/anamnese/anamnese_wizard_screen.dart` (support an "edit mode" so it can be reused post-onboarding without forcing navigation into `/onboarding/contacts`)
- Modify: `mobile/lib/features/trusted_contacts/trusted_contacts_screen.dart` (add a delete affordance per contact, calling the existing `TrustedContactsRepository.remove(id)`)
- Create: `mobile/lib/features/settings/settings_screen.dart` (new screen: edit/delete sensory profile, link to manage contacts, sign out)
- Modify: `mobile/lib/features/home/home_screen.dart` (add an entry point — e.g. an AppBar icon — to the new settings screen)
- Modify: `mobile/lib/main.dart` (register the new route)

**Interfaces:**
- Consumes: `SensoryProfileRepository` (Task 12), `TrustedContactsRepository` (Task 13), `AuthService` (Task 9), existing `AnamneseWizardScreen` and `TrustedContactsScreen`.
- Produces: `SensoryProfileService.remove(firebaseUid): Promise<void>` / `DELETE /sensory-profile` (scoped by `userId` derived from the verified token, same tenant-isolation pattern as every other service). `SensoryProfileRepository.remove(): Future<void>`. A reachable settings/management screen from `/home`.

**Global constraints that bind this task (same as the rest of the plan):**
- Tenant isolation stays application-layer only — `remove()` must scope by `userId` derived server-side, never a client-supplied id.
- No new business data goes to Firebase.
- Deleting the sensory profile or a contact must be an explicit, confirmed user action (confirmation dialog before either delete) — this is destructive, irreversible data loss from the user's perspective.

---

## Plan Self-Review Notes

- **Spec coverage:** Onboarding flow (Tasks 9, 11), anamnese wizard 4 steps (Task 12), trusted contacts + consent (Tasks 6, 13), emergency wa.me flow (Tasks 7, 14), tenant isolation via app-layer `user_id` scoping (Tasks 4–7, enforced in every service method), Firebase Auth + Postgres integration (Tasks 2–3), e2e coverage of the full chain (Task 8). All spec sections have a corresponding task.
- **Type consistency:** `OnboardingStatus`/`TrustedContact`/`EmergencyMessage` field names match between backend response shapes (Tasks 4, 6, 7) and Flutter `fromJson` models (Tasks 11, 13, 14). `RELACOES` enum values (`PSICOLOGO`, `PSIQUIATRA`, `T.O.`, `FAMILIAR`, `OUTRO`) are identical in the backend DTO (Task 6) and the Flutter dropdown (Task 13).
- **Deferred infra decision:** Postgres hosting for production (Neon vs. Supabase-as-DB-only) is intentionally left open per the spec — Task 1 uses local docker-compose for development, and the hosting choice does not block any task in this plan.
