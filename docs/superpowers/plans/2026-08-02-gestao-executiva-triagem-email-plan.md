# Sincro — Gestão Executiva: Triagem de E-mail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Sincro user connect their Gmail (readonly) and see a calm inbox summary on the Home screen — which emails "need attention" vs. "can wait" — classified by a pluggable heuristic (plano `simples`) or LLM (plano `pro`) classifier, with an aggregated background-synced push notification, and full delete-on-disconnect.

**Architecture:** Extends the existing NestJS + Prisma + PostgreSQL backend and Flutter + Riverpod mobile client from `docs/superpowers/plans/2026-08-01-onboarding-anamnese-rede-apoio-plan.md`. Gmail OAuth (`serverAuthCode` flow — mobile obtains it via native Google Sign-In, backend exchanges it for tokens; no public redirect URI needed) is mediated entirely by the backend; the backend is the only thing that ever talks to the Gmail API. Background sync runs in-process via `@nestjs/schedule` (no new infra). Only derived summaries (never email bodies) are persisted.

**Tech Stack:** Adds to the existing stack: `googleapis` (Gmail API + OAuth2 client), `@anthropic-ai/sdk` (LLM classification), `@nestjs/schedule` (background sync), `firebase-admin` messaging (already installed, unused messaging module), `google_sign_in` + `firebase_messaging` (Flutter).

## Global Constraints

- New table/column names use the Portuguese names fixed in the design spec: `conexoes_gmail`, `resumos_email`, `refresh_token_criptografado`, `gmail_email`, `last_history_id`, `ultima_sincronizacao`, `gmail_message_id`, `remetente`, `assunto`, `resumo_curto`, `categoria`, `recebido_em`, `lido_no_app`, `plano`.
- Tenant isolation stays application-layer only: every repository/service call scopes by `user_id` derived from the verified Firebase token — never a client-supplied parameter. Same pattern as every Fase 1 service (`UsersService.getByFirebaseUidOrThrow`).
- Every new tenant-scoped table gets `@@index([userId])` from its first migration — Fase 1's final review had to add this after the fact for `contatos_confianca`; don't repeat that gap here.
- The Gmail OAuth scope requested is `gmail.readonly` only — never `gmail.send`/`gmail.modify`.
- The full email body is never persisted anywhere — only `remetente`, `assunto`, and a derived `resumoCurto` land in Postgres. `GmailApiClient` fetches messages with `format: 'metadata'` (never the full body) plus the Gmail-provided `snippet`, so the full body never even reaches the backend process.
- Push notifications are always aggregated per sync cycle ("N e-mails precisam de atenção") — never one notification per email.
- `toleranciaNotificacao` gating: `PADRAO` → push allowed. `SILENCIOSAS` and `HORARIO_ESPECIFICO` → no push (Fase 1's anamnese wizard never actually collected a time window for `HORARIO_ESPECIFICO`, only the category — until that's fixed, treating it as silent is the safer choice than guessing a window). The in-app summary is available either way regardless of push.
- Categoria enum values are exactly: `PRECISA_ATENCAO`, `PODE_ESPERAR`.
- Plano values are exactly: `simples`, `pro`. No billing/checkout flow — `plano` is a plain column, manually adjustable for now.
- Exact package versions may drift from what's listed above (Fase 1 hit this with Prisma resolving to v7 instead of v5, and `flutter_riverpod` resolving to v3 instead of the classic `StateNotifier` API) — if a task's literal code doesn't compile/run against what actually installs, adapt it the same way Fase 1 did: diagnose the real error, fix with the minimal change that makes the intent work, and document the deviation and why in the task's commit/report. Don't guess blindly.

## Prerequisites (external setup, needed before Task 3)

These need to exist before Task 3 (Gmail OAuth) can be dispatched — they require a human with access to the Google Cloud / Firebase console for the `sincro-3ac01` project (the same project Fase 1 already created):

1. **Enable the Gmail API** for the `sincro-3ac01` Google Cloud project (APIs & Services → Enable APIs → "Gmail API").
2. **Create an OAuth 2.0 Web Client ID** (APIs & Services → Credentials → Create Credentials → OAuth client ID → Application type: Web application) in the same project. This single Web Client ID/secret pair is used both as the mobile app's `serverClientId` (for `google_sign_in` to request offline access) and by the backend to exchange the resulting `serverAuthCode` for tokens. No redirect URI needs to be configured for this flow.
3. Note the **Client ID** and **Client Secret** — needed for `backend/.env`'s `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`, and the Client ID again for mobile's `GOOGLE_WEB_CLIENT_ID` build define (Task 8).
4. **Get an Anthropic API key** (needed for Task 4's `LlmEmailClassifier` / plano `pro`) — `backend/.env`'s `ANTHROPIC_API_KEY`.
5. Generate a **32-byte base64 encryption key** for `TOKEN_ENCRYPTION_KEY` (Task 2) — the implementer can generate this themselves with `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`, no external service needed.

If dispatching via subagent-driven-development: pause before Task 3 and confirm items 1-4 are in place (ask the human partner), the same way Fase 1 paused for Docker Desktop and the Firebase project.

---

## Backend (NestJS)

### Task 1: Prisma schema — Gmail connections, email summaries, plano

**Files:**
- Modify: `backend/prisma/schema.prisma`
- Create: `backend/prisma/migrations/<timestamp>_add_email_triage/migration.sql` (generated by `prisma migrate dev`)

**Interfaces:**
- Produces: Prisma models `GmailConnection` (table `conexoes_gmail`), `EmailSummary` (table `resumos_email`), and a new `plano`/`fcmToken` column on `User`.

- [ ] **Step 1: Add the new models and columns to the schema**

Modify `backend/prisma/schema.prisma`:
```prisma
model User {
  id              String           @id @default(uuid())
  firebaseUid     String           @unique @map("firebase_uid")
  nome            String
  createdAt       DateTime         @default(now()) @map("created_at")
  plano           String           @default("simples")
  fcmToken        String?          @map("fcm_token")
  sensoryProfile  SensoryProfile?
  trustedContacts TrustedContact[]
  gmailConnection GmailConnection?
  emailSummaries  EmailSummary[]

  @@map("usuarios")
}

model GmailConnection {
  id                        String    @id @default(uuid())
  userId                    String    @unique @map("user_id")
  user                      User      @relation(fields: [userId], references: [id])
  refreshTokenCriptografado String    @map("refresh_token_criptografado")
  gmailEmail                String    @map("gmail_email")
  lastHistoryId             String?   @map("last_history_id")
  ultimaSincronizacao       DateTime? @map("ultima_sincronizacao")
  criadoEm                  DateTime  @default(now()) @map("criado_em")

  @@map("conexoes_gmail")
}

model EmailSummary {
  id             String   @id @default(uuid())
  userId         String   @map("user_id")
  user           User     @relation(fields: [userId], references: [id])
  gmailMessageId String   @map("gmail_message_id")
  remetente      String
  assunto        String
  resumoCurto    String   @map("resumo_curto")
  categoria      String
  recebidoEm     DateTime @map("recebido_em")
  lidoNoApp      Boolean  @default(false) @map("lido_no_app")
  criadoEm       DateTime @default(now()) @map("criado_em")

  @@unique([userId, gmailMessageId])
  @@index([userId])
  @@map("resumos_email")
}
```

Leave `SensoryProfile` and `TrustedContact` models exactly as they are — only `User` gains two new fields (`plano`, `fcmToken`) and two new relations (`gmailConnection`, `emailSummaries`).

- [ ] **Step 2: Run the migration**

```bash
cd backend
docker ps  # confirm backend-postgres-1 is up; if not: docker compose -f docker-compose.yml up -d
npx prisma migrate dev --name add_email_triage
```
Expected: migration applied, Prisma Client regenerated, no errors. If Prisma's CLI/schema syntax differs from what's shown above (Fase 1 hit exactly this with the v5→v7 jump), adapt following the pattern `backend/prisma/schema.prisma`'s existing models already use — they're the source of truth for whatever Prisma version is actually installed.

- [ ] **Step 3: Verify with `prisma migrate status`**

```bash
npx prisma migrate status
```
Expected: "Database schema is up to date!"

- [ ] **Step 4: Commit**

```bash
git add backend/prisma
git commit -m "feat: add Prisma schema for Gmail connections, email summaries, and plano"
```

---

### Task 2: Token encryption utility

**Files:**
- Create: `backend/src/crypto/token-crypto.service.ts`
- Create: `backend/src/crypto/crypto.module.ts`
- Test: `backend/src/crypto/token-crypto.service.spec.ts`
- Modify: `backend/.env.example`

**Interfaces:**
- Consumes: `process.env.TOKEN_ENCRYPTION_KEY` (base64-encoded 32-byte key).
- Produces: `TokenCryptoService.encrypt(plaintext: string): string`, `TokenCryptoService.decrypt(encoded: string): string`, exported from `CryptoModule`. Consumed by Task 3's `GmailConnectionsService`.

- [ ] **Step 1: Write the failing test**

`backend/src/crypto/token-crypto.service.spec.ts`:
```typescript
import { TokenCryptoService } from './token-crypto.service';
import { randomBytes } from 'crypto';

describe('TokenCryptoService', () => {
  const originalEnv = process.env.TOKEN_ENCRYPTION_KEY;

  beforeEach(() => {
    process.env.TOKEN_ENCRYPTION_KEY = randomBytes(32).toString('base64');
  });

  afterEach(() => {
    process.env.TOKEN_ENCRYPTION_KEY = originalEnv;
  });

  it('round-trips a plaintext string through encrypt and decrypt', () => {
    const service = new TokenCryptoService();
    const ciphertext = service.encrypt('meu-refresh-token-secreto');

    expect(ciphertext).not.toBe('meu-refresh-token-secreto');
    expect(service.decrypt(ciphertext)).toBe('meu-refresh-token-secreto');
  });

  it('produces different ciphertext for the same plaintext on repeated calls', () => {
    const service = new TokenCryptoService();
    const a = service.encrypt('mesmo-valor');
    const b = service.encrypt('mesmo-valor');

    expect(a).not.toBe(b);
  });

  it('throws when the ciphertext has been tampered with', () => {
    const service = new TokenCryptoService();
    const ciphertext = service.encrypt('valor-original');
    const tampered = ciphertext.slice(0, -4) + 'AAAA';

    expect(() => service.decrypt(tampered)).toThrow();
  });

  it('throws at construction time when TOKEN_ENCRYPTION_KEY is missing', () => {
    delete process.env.TOKEN_ENCRYPTION_KEY;

    expect(() => new TokenCryptoService()).toThrow('TOKEN_ENCRYPTION_KEY');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend
npx jest src/crypto/token-crypto.service.spec.ts
```
Expected: FAIL — `Cannot find module './token-crypto.service'`.

- [ ] **Step 3: Implement TokenCryptoService**

`backend/src/crypto/token-crypto.service.ts`:
```typescript
import { Injectable } from '@nestjs/common';
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

const IV_LENGTH_BYTES = 12;
const AUTH_TAG_LENGTH_BYTES = 16;

@Injectable()
export class TokenCryptoService {
  private readonly key: Buffer;

  constructor() {
    const keyBase64 = process.env.TOKEN_ENCRYPTION_KEY;
    if (!keyBase64) {
      throw new Error(
        'TOKEN_ENCRYPTION_KEY is not set. Generate one with: ' +
          `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`,
      );
    }
    this.key = Buffer.from(keyBase64, 'base64');
    if (this.key.length !== 32) {
      throw new Error('TOKEN_ENCRYPTION_KEY must decode to exactly 32 bytes (AES-256).');
    }
  }

  encrypt(plaintext: string): string {
    const iv = randomBytes(IV_LENGTH_BYTES);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    const authTag = cipher.getAuthTag();
    return Buffer.concat([iv, authTag, ciphertext]).toString('base64');
  }

  decrypt(encoded: string): string {
    const buffer = Buffer.from(encoded, 'base64');
    const iv = buffer.subarray(0, IV_LENGTH_BYTES);
    const authTag = buffer.subarray(IV_LENGTH_BYTES, IV_LENGTH_BYTES + AUTH_TAG_LENGTH_BYTES);
    const ciphertext = buffer.subarray(IV_LENGTH_BYTES + AUTH_TAG_LENGTH_BYTES);
    const decipher = createDecipheriv('aes-256-gcm', this.key, iv);
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
  }
}
```

`backend/src/crypto/crypto.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { TokenCryptoService } from './token-crypto.service';

@Module({
  providers: [TokenCryptoService],
  exports: [TokenCryptoService],
})
export class CryptoModule {}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
npx jest src/crypto/token-crypto.service.spec.ts
```
Expected: PASS, 4 tests.

- [ ] **Step 5: Add the env var to `.env.example` and generate one for local `.env`**

Modify `backend/.env.example`, append:
```
TOKEN_ENCRYPTION_KEY=""
GOOGLE_CLIENT_ID=""
GOOGLE_CLIENT_SECRET=""
ANTHROPIC_API_KEY=""
```

Generate a real value for local `backend/.env` (gitignored, not committed):
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```
Paste the output as `TOKEN_ENCRYPTION_KEY` in `backend/.env`. Leave `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`/`ANTHROPIC_API_KEY` blank for now — Tasks 3 and 4 need them populated with real values from the Prerequisites section before their own verification steps will pass.

- [ ] **Step 6: Commit**

```bash
git add backend/src/crypto backend/.env.example
git commit -m "feat: add AES-256-GCM token encryption utility"
```

---

### Task 3: Gmail OAuth module (connection, API client)

**Files:**
- Create: `backend/src/gmail/gmail-oauth.service.ts`
- Create: `backend/src/gmail/gmail-api-client.service.ts`
- Create: `backend/src/gmail/gmail-connections.service.ts`
- Create: `backend/src/gmail/gmail.controller.ts`
- Create: `backend/src/gmail/gmail.module.ts`
- Create: `backend/src/gmail/dto/connect-gmail.dto.ts`
- Test: `backend/src/gmail/gmail-oauth.service.spec.ts`
- Test: `backend/src/gmail/gmail-connections.service.spec.ts`
- Modify: `backend/src/app.module.ts`
- Modify: `backend/package.json` (add `googleapis`)

**Interfaces:**
- Consumes: `UsersService.getByFirebaseUidOrThrow` (Fase 1), `TokenCryptoService` (Task 2), `PrismaService`.
- Produces: `GmailOAuthService` (`exchangeServerAuthCode`, `authenticatedClientFor`, `getEmailAddress`, `revoke`), `GmailApiClient` (`fetchInitialUnread`, `fetchIncremental`, both consumed by Task 5), `GmailConnectionsService` (`connect`, `status`, `disconnect`, `getDecryptedRefreshToken` — the last one consumed by Task 5). Routes: `POST /gmail/connect`, `GET /gmail/connection`, `DELETE /gmail/connection`.

**⚠️ Requires Prerequisites items 1-3** (Gmail API enabled, OAuth Web Client created, `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` set in `backend/.env`) before Step 6's verification will actually succeed against real Google infrastructure — the unit tests in Steps 1-5 don't need real credentials (they mock `googleapis`), but confirm the prerequisites are done before starting this task.

- [ ] **Step 1: Install the Gmail API client library**

```bash
cd backend
npm install googleapis
```

- [ ] **Step 2: Write the failing GmailOAuthService test**

`backend/src/gmail/gmail-oauth.service.spec.ts`:
```typescript
import { GmailOAuthService } from './gmail-oauth.service';

jest.mock('googleapis', () => {
  const mockOAuth2Client = {
    getToken: jest.fn(),
    setCredentials: jest.fn(),
    revokeToken: jest.fn(),
  };
  return {
    google: {
      auth: { OAuth2: jest.fn(() => mockOAuth2Client) },
      oauth2: jest.fn(() => ({ userinfo: { get: jest.fn() } })),
    },
    __mockOAuth2Client: mockOAuth2Client,
  };
});

describe('GmailOAuthService', () => {
  beforeEach(() => {
    process.env.GOOGLE_CLIENT_ID = 'test-client-id';
    process.env.GOOGLE_CLIENT_SECRET = 'test-client-secret';
  });

  it('exchanges a serverAuthCode for a refresh token', async () => {
    const { google } = jest.requireMock('googleapis');
    const mockClient = google.auth.OAuth2();
    mockClient.getToken.mockResolvedValue({ tokens: { refresh_token: 'rt-123', access_token: 'at-123' } });

    const service = new GmailOAuthService();
    const result = await service.exchangeServerAuthCode('code-abc');

    expect(result).toEqual({ refreshToken: 'rt-123' });
    expect(mockClient.getToken).toHaveBeenCalledWith('code-abc');
  });

  it('throws a clear error when Google does not return a refresh token', async () => {
    const { google } = jest.requireMock('googleapis');
    const mockClient = google.auth.OAuth2();
    mockClient.getToken.mockResolvedValue({ tokens: { access_token: 'at-123' } });

    const service = new GmailOAuthService();

    await expect(service.exchangeServerAuthCode('code-abc')).rejects.toThrow(/refresh token/i);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

```bash
npx jest src/gmail/gmail-oauth.service.spec.ts
```
Expected: FAIL — `Cannot find module './gmail-oauth.service'`.

- [ ] **Step 4: Implement GmailOAuthService and GmailApiClient**

`backend/src/gmail/gmail-oauth.service.ts`:
```typescript
import { Injectable } from '@nestjs/common';
import { google } from 'googleapis';

@Injectable()
export class GmailOAuthService {
  private buildClient() {
    return new google.auth.OAuth2(process.env.GOOGLE_CLIENT_ID, process.env.GOOGLE_CLIENT_SECRET);
  }

  async exchangeServerAuthCode(serverAuthCode: string): Promise<{ refreshToken: string }> {
    const client = this.buildClient();
    const { tokens } = await client.getToken(serverAuthCode);
    if (!tokens.refresh_token) {
      throw new Error(
        'O Google não retornou um refresh token. Isso geralmente acontece quando o acesso já ' +
          'foi concedido antes — revogue o acesso em https://myaccount.google.com/permissions ' +
          'e tente conectar novamente.',
      );
    }
    return { refreshToken: tokens.refresh_token };
  }

  authenticatedClientFor(refreshToken: string) {
    const client = this.buildClient();
    client.setCredentials({ refresh_token: refreshToken });
    return client;
  }

  async getEmailAddress(refreshToken: string): Promise<string> {
    const auth = this.authenticatedClientFor(refreshToken);
    const { data } = await google.oauth2('v2').userinfo.get({ auth });
    return data.email ?? '';
  }

  async revoke(refreshToken: string): Promise<void> {
    const client = this.authenticatedClientFor(refreshToken);
    await client.revokeToken(refreshToken);
  }
}
```

`backend/src/gmail/gmail-api-client.service.ts`:
```typescript
import { Injectable } from '@nestjs/common';
import { google, gmail_v1 } from 'googleapis';
import { GmailOAuthService } from './gmail-oauth.service';

export interface FetchedEmail {
  gmailMessageId: string;
  remetente: string;
  assunto: string;
  corpo: string;
  recebidoEm: Date;
}

@Injectable()
export class GmailApiClient {
  constructor(private readonly oauthService: GmailOAuthService) {}

  private gmailFor(refreshToken: string): gmail_v1.Gmail {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    return google.gmail({ version: 'v1', auth });
  }

  /** First sync for a newly connected account: unread messages from the last 7 days, capped at 50. */
  async fetchInitialUnread(refreshToken: string): Promise<{ emails: FetchedEmail[]; historyId: string | null }> {
    const gmail = this.gmailFor(refreshToken);
    const sevenDaysAgoUnixSeconds = Math.floor((Date.now() - 7 * 24 * 60 * 60 * 1000) / 1000);
    const list = await gmail.users.messages.list({
      userId: 'me',
      q: `is:unread after:${sevenDaysAgoUnixSeconds}`,
      maxResults: 50,
    });
    const messageIds = (list.data.messages ?? []).map((m) => m.id!);
    const emails = await this.fetchMessages(gmail, messageIds);
    const profile = await gmail.users.getProfile({ userId: 'me' });
    return { emails, historyId: profile.data.historyId ?? null };
  }

  /** Incremental sync using a previously stored historyId. */
  async fetchIncremental(
    refreshToken: string,
    sinceHistoryId: string,
  ): Promise<{ emails: FetchedEmail[]; historyId: string | null; historyExpired: boolean }> {
    const gmail = this.gmailFor(refreshToken);
    try {
      const history = await gmail.users.history.list({
        userId: 'me',
        startHistoryId: sinceHistoryId,
        historyTypes: ['messageAdded'],
      });
      const messageIds = new Set<string>();
      for (const record of history.data.history ?? []) {
        for (const added of record.messagesAdded ?? []) {
          if (added.message?.id) messageIds.add(added.message.id);
        }
      }
      const emails = await this.fetchMessages(gmail, Array.from(messageIds));
      return { emails, historyId: history.data.historyId ?? sinceHistoryId, historyExpired: false };
    } catch (error: unknown) {
      // Gmail returns 404 when the stored historyId is too old (beyond Gmail's retention window).
      const status = (error as { code?: number })?.code;
      if (status === 404) {
        return { emails: [], historyId: null, historyExpired: true };
      }
      throw error;
    }
  }

  private async fetchMessages(gmail: gmail_v1.Gmail, ids: string[]): Promise<FetchedEmail[]> {
    const emails: FetchedEmail[] = [];
    for (const id of ids) {
      const message = await gmail.users.messages.get({
        userId: 'me',
        id,
        format: 'metadata',
        metadataHeaders: ['From', 'Subject'],
      });
      const headers = message.data.payload?.headers ?? [];
      const getHeader = (name: string) => headers.find((h) => h.name === name)?.value ?? '';
      emails.push({
        gmailMessageId: id,
        remetente: getHeader('From'),
        assunto: getHeader('Subject'),
        corpo: message.data.snippet ?? '',
        recebidoEm: new Date(Number(message.data.internalDate ?? Date.now())),
      });
    }
    return emails;
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
npx jest src/gmail/gmail-oauth.service.spec.ts
```
Expected: PASS, 2 tests.

- [ ] **Step 6: Write the failing GmailConnectionsService test**

`backend/src/gmail/gmail-connections.service.spec.ts`:
```typescript
import { GmailConnectionsService } from './gmail-connections.service';

function buildDeps() {
  const prisma = {
    gmailConnection: {
      upsert: jest.fn(),
      findUnique: jest.fn(),
      deleteMany: jest.fn(),
    },
    emailSummary: { deleteMany: jest.fn() },
  };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
  const tokenCrypto = {
    encrypt: jest.fn((v: string) => `encrypted(${v})`),
    decrypt: jest.fn((v: string) => v.replace('encrypted(', '').replace(')', '')),
  };
  const oauthService = {
    exchangeServerAuthCode: jest.fn().mockResolvedValue({ refreshToken: 'rt-123' }),
    getEmailAddress: jest.fn().mockResolvedValue('ana@example.com'),
    revoke: jest.fn().mockResolvedValue(undefined),
  };
  return { prisma, usersService, tokenCrypto, oauthService };
}

describe('GmailConnectionsService', () => {
  it('connects a new account, encrypting the refresh token before storing it', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.upsert.mockResolvedValue({ id: 'gc1' });
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await service.connect('fb1', 'auth-code-abc');

    expect(oauthService.exchangeServerAuthCode).toHaveBeenCalledWith('auth-code-abc');
    expect(tokenCrypto.encrypt).toHaveBeenCalledWith('rt-123');
    expect(prisma.gmailConnection.upsert).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      update: { refreshTokenCriptografado: 'encrypted(rt-123)', gmailEmail: 'ana@example.com' },
      create: { userId: 'u1', refreshTokenCriptografado: 'encrypted(rt-123)', gmailEmail: 'ana@example.com' },
    });
  });

  it('reports connection status scoped to the resolved user', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue({ gmailEmail: 'ana@example.com' });
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    const status = await service.status('fb1');

    expect(prisma.gmailConnection.findUnique).toHaveBeenCalledWith({ where: { userId: 'u1' } });
    expect(status).toEqual({ connected: true, gmailEmail: 'ana@example.com' });
  });

  it('reports not connected when there is no row', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue(null);
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    const status = await service.status('fb1');

    expect(status).toEqual({ connected: false, gmailEmail: null });
  });

  it('disconnect revokes the token with Google and deletes both the connection and its summaries', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue({ refreshTokenCriptografado: 'encrypted(rt-123)' });
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await service.disconnect('fb1');

    expect(oauthService.revoke).toHaveBeenCalledWith('rt-123');
    expect(prisma.emailSummary.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } });
    expect(prisma.gmailConnection.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } });
  });

  it('disconnect is a no-op-safe call when there is nothing to disconnect', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue(null);
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await service.disconnect('fb1');

    expect(oauthService.revoke).not.toHaveBeenCalled();
    expect(prisma.gmailConnection.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } });
  });
});
```

- [ ] **Step 7: Run test to verify it fails**

```bash
npx jest src/gmail/gmail-connections.service.spec.ts
```
Expected: FAIL — `Cannot find module './gmail-connections.service'`.

- [ ] **Step 8: Implement GmailConnectionsService, DTO, controller, module**

`backend/src/gmail/gmail-connections.service.ts`:
```typescript
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { TokenCryptoService } from '../crypto/token-crypto.service';
import { GmailOAuthService } from './gmail-oauth.service';

@Injectable()
export class GmailConnectionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    private readonly tokenCrypto: TokenCryptoService,
    private readonly oauthService: GmailOAuthService,
  ) {}

  async connect(firebaseUid: string, serverAuthCode: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const { refreshToken } = await this.oauthService.exchangeServerAuthCode(serverAuthCode);
    const gmailEmail = await this.oauthService.getEmailAddress(refreshToken);
    const refreshTokenCriptografado = this.tokenCrypto.encrypt(refreshToken);

    return this.prisma.gmailConnection.upsert({
      where: { userId: user.id },
      update: { refreshTokenCriptografado, gmailEmail },
      create: { userId: user.id, refreshTokenCriptografado, gmailEmail },
    });
  }

  async status(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId: user.id } });
    return { connected: connection !== null, gmailEmail: connection?.gmailEmail ?? null };
  }

  async getDecryptedRefreshToken(userId: string): Promise<string | null> {
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId } });
    if (!connection) return null;
    return this.tokenCrypto.decrypt(connection.refreshTokenCriptografado);
  }

  async disconnect(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId: user.id } });
    if (connection) {
      const refreshToken = this.tokenCrypto.decrypt(connection.refreshTokenCriptografado);
      await this.oauthService.revoke(refreshToken);
    }
    await this.prisma.emailSummary.deleteMany({ where: { userId: user.id } });
    await this.prisma.gmailConnection.deleteMany({ where: { userId: user.id } });
  }
}
```

`backend/src/gmail/dto/connect-gmail.dto.ts`:
```typescript
import { IsString, MinLength } from 'class-validator';

export class ConnectGmailDto {
  @IsString()
  @MinLength(1)
  serverAuthCode: string;
}
```

`backend/src/gmail/gmail.controller.ts`:
```typescript
import { Body, Controller, Delete, Get, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { GmailConnectionsService } from './gmail-connections.service';
import { ConnectGmailDto } from './dto/connect-gmail.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('gmail')
export class GmailController {
  constructor(private readonly connectionsService: GmailConnectionsService) {}

  @Post('connect')
  async connect(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: ConnectGmailDto) {
    await this.connectionsService.connect(firebaseUid, dto.serverAuthCode);
    return { success: true };
  }

  @Get('connection')
  async status(@CurrentFirebaseUid() firebaseUid: string) {
    return this.connectionsService.status(firebaseUid);
  }

  @Delete('connection')
  async disconnect(@CurrentFirebaseUid() firebaseUid: string) {
    await this.connectionsService.disconnect(firebaseUid);
    return { success: true };
  }
}
```

`backend/src/gmail/gmail.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { UsersModule } from '../users/users.module';
import { CryptoModule } from '../crypto/crypto.module';
import { GmailOAuthService } from './gmail-oauth.service';
import { GmailApiClient } from './gmail-api-client.service';
import { GmailConnectionsService } from './gmail-connections.service';
import { GmailController } from './gmail.controller';

@Module({
  imports: [UsersModule, CryptoModule],
  providers: [GmailOAuthService, GmailApiClient, GmailConnectionsService],
  controllers: [GmailController],
  exports: [GmailOAuthService, GmailApiClient, GmailConnectionsService],
})
export class GmailModule {}
```

Modify `backend/src/app.module.ts` to add `GmailModule` to `imports` (preserve every existing entry — `PrismaModule`, `AuthModule`, `UsersModule`, `SensoryProfileModule`, `TrustedContactsModule`, `EmergencyModule`):
```typescript
import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { SensoryProfileModule } from './sensory-profile/sensory-profile.module';
import { TrustedContactsModule } from './trusted-contacts/trusted-contacts.module';
import { EmergencyModule } from './emergency/emergency.module';
import { GmailModule } from './gmail/gmail.module';

@Module({
  imports: [
    PrismaModule,
    AuthModule,
    UsersModule,
    SensoryProfileModule,
    TrustedContactsModule,
    EmergencyModule,
    GmailModule,
  ],
})
export class AppModule {}
```

- [ ] **Step 9: Run test to verify it passes**

```bash
npx jest src/gmail/gmail-connections.service.spec.ts
```
Expected: PASS, 5 tests.

- [ ] **Step 10: Manual smoke check that the app still boots**

```bash
npm run start:dev
```
Expected: `Nest application successfully started`, no errors (this doesn't require real Google credentials — nothing calls Google at boot time). Stop it (Ctrl+C).

- [ ] **Step 11: Commit**

```bash
git add backend/src/gmail backend/src/app.module.ts backend/package.json backend/package-lock.json
git commit -m "feat: add Gmail OAuth connection module (serverAuthCode flow, readonly scope)"
```

---

### Task 4: Email classifiers (heuristic + LLM)

**Files:**
- Create: `backend/src/email-classification/email-classifier.interface.ts`
- Create: `backend/src/email-classification/heuristic-email-classifier.service.ts`
- Create: `backend/src/email-classification/llm-email-classifier.service.ts`
- Create: `backend/src/email-classification/email-classification.module.ts`
- Test: `backend/src/email-classification/heuristic-email-classifier.service.spec.ts`
- Test: `backend/src/email-classification/llm-email-classifier.service.spec.ts`
- Modify: `backend/package.json` (add `@anthropic-ai/sdk`)

**Interfaces:**
- Consumes: nothing from earlier tasks (self-contained).
- Produces: `EmailClassifier` interface (`classify(email, context): Promise<EmailClassification>`), `HeuristicEmailClassifier`, `LlmEmailClassifier`, both exported from `EmailClassificationModule`. Consumed by Task 5's `EmailSyncService`.

- [ ] **Step 1: Install the Anthropic SDK**

```bash
cd backend
npm install @anthropic-ai/sdk
```

- [ ] **Step 2: Write the failing heuristic classifier test**

`backend/src/email-classification/heuristic-email-classifier.service.spec.ts`:
```typescript
import { HeuristicEmailClassifier } from './heuristic-email-classifier.service';

describe('HeuristicEmailClassifier', () => {
  const classifier = new HeuristicEmailClassifier();

  it('classifies as PRECISA_ATENCAO when the subject contains an urgency keyword', async () => {
    const result = await classifier.classify(
      { remetente: 'banco@example.com', assunto: 'Fatura com vencimento amanhã', corpo: 'Pague até amanhã.' },
      {},
    );

    expect(result.categoria).toBe('PRECISA_ATENCAO');
  });

  it('classifies as PRECISA_ATENCAO when the body contains an urgency keyword even if the subject does not', async () => {
    const result = await classifier.classify(
      { remetente: 'rh@example.com', assunto: 'Atualização', corpo: 'Ação necessária até sexta-feira.' },
      {},
    );

    expect(result.categoria).toBe('PRECISA_ATENCAO');
  });

  it('classifies as PODE_ESPERAR when there is no urgency keyword', async () => {
    const result = await classifier.classify(
      { remetente: 'newsletter@example.com', assunto: 'Novidades da semana', corpo: 'Confira o que rolou.' },
      {},
    );

    expect(result.categoria).toBe('PODE_ESPERAR');
  });

  it('truncates a long subject to build resumoCurto', async () => {
    const longSubject = 'A'.repeat(150);
    const result = await classifier.classify({ remetente: 'x@example.com', assunto: longSubject, corpo: '' }, {});

    expect(result.resumoCurto.length).toBeLessThanOrEqual(100);
    expect(result.resumoCurto.endsWith('...')).toBe(true);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

```bash
npx jest src/email-classification/heuristic-email-classifier.service.spec.ts
```
Expected: FAIL — `Cannot find module './heuristic-email-classifier.service'`.

- [ ] **Step 4: Implement the interface and heuristic classifier**

`backend/src/email-classification/email-classifier.interface.ts`:
```typescript
export interface EmailToClassify {
  remetente: string;
  assunto: string;
  corpo: string;
}

export interface EmailClassificationContext {
  tomPreferido?: string;
}

export interface EmailClassification {
  categoria: 'PRECISA_ATENCAO' | 'PODE_ESPERAR';
  resumoCurto: string;
}

export interface EmailClassifier {
  classify(email: EmailToClassify, context: EmailClassificationContext): Promise<EmailClassification>;
}
```

`backend/src/email-classification/heuristic-email-classifier.service.ts`:
```typescript
import { Injectable } from '@nestjs/common';
import {
  EmailClassification,
  EmailClassificationContext,
  EmailClassifier,
  EmailToClassify,
} from './email-classifier.interface';

const PALAVRAS_CHAVE_URGENTES = ['urgente', 'prazo', 'vencimento', 'vence', 'ação necessária', 'importante'];
const RESUMO_MAX_LENGTH = 100;

@Injectable()
export class HeuristicEmailClassifier implements EmailClassifier {
  async classify(email: EmailToClassify, _context: EmailClassificationContext): Promise<EmailClassification> {
    const assuntoLower = email.assunto.toLowerCase();
    const corpoLower = email.corpo.toLowerCase();
    const temPalavraChave = PALAVRAS_CHAVE_URGENTES.some(
      (palavra) => assuntoLower.includes(palavra) || corpoLower.includes(palavra),
    );

    return {
      categoria: temPalavraChave ? 'PRECISA_ATENCAO' : 'PODE_ESPERAR',
      resumoCurto: this.truncate(email.assunto),
    };
  }

  private truncate(subject: string): string {
    if (subject.length <= RESUMO_MAX_LENGTH) return subject;
    return `${subject.slice(0, RESUMO_MAX_LENGTH - 3)}...`;
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
npx jest src/email-classification/heuristic-email-classifier.service.spec.ts
```
Expected: PASS, 4 tests.

- [ ] **Step 6: Write the failing LLM classifier test**

`backend/src/email-classification/llm-email-classifier.service.spec.ts`:
```typescript
import { LlmEmailClassifier } from './llm-email-classifier.service';

function buildFakeAnthropicClient(responseText: string) {
  return {
    messages: {
      create: jest.fn().mockResolvedValue({
        content: [{ type: 'text', text: responseText }],
      }),
    },
  };
}

describe('LlmEmailClassifier', () => {
  it('parses the JSON response into a classification', async () => {
    const fakeClient = buildFakeAnthropicClient('{"categoria":"PRECISA_ATENCAO","resumoCurto":"Fatura vence amanhã"}');
    const classifier = new LlmEmailClassifier(fakeClient as any);

    const result = await classifier.classify(
      { remetente: 'banco@example.com', assunto: 'Fatura', corpo: 'Vence amanhã.' },
      { tomPreferido: 'DIRETO_E_CURTO' },
    );

    expect(result).toEqual({ categoria: 'PRECISA_ATENCAO', resumoCurto: 'Fatura vence amanhã' });
    expect(fakeClient.messages.create).toHaveBeenCalledWith(
      expect.objectContaining({
        messages: [expect.objectContaining({ content: expect.stringContaining('Fatura') })],
      }),
    );
  });

  it('falls back to PODE_ESPERAR with the subject as the summary when the model response is not valid JSON', async () => {
    const fakeClient = buildFakeAnthropicClient('não é json');
    const classifier = new LlmEmailClassifier(fakeClient as any);

    const result = await classifier.classify(
      { remetente: 'x@example.com', assunto: 'Assunto original', corpo: '' },
      {},
    );

    expect(result).toEqual({ categoria: 'PODE_ESPERAR', resumoCurto: 'Assunto original' });
  });

  it('falls back to PODE_ESPERAR when the API call itself throws', async () => {
    const fakeClient = { messages: { create: jest.fn().mockRejectedValue(new Error('network error')) } };
    const classifier = new LlmEmailClassifier(fakeClient as any);

    const result = await classifier.classify({ remetente: 'x@example.com', assunto: 'Assunto', corpo: '' }, {});

    expect(result).toEqual({ categoria: 'PODE_ESPERAR', resumoCurto: 'Assunto' });
  });
});
```

- [ ] **Step 7: Run test to verify it fails**

```bash
npx jest src/email-classification/llm-email-classifier.service.spec.ts
```
Expected: FAIL — `Cannot find module './llm-email-classifier.service'`.

- [ ] **Step 8: Implement LlmEmailClassifier**

`backend/src/email-classification/llm-email-classifier.service.ts`:
```typescript
import { Injectable, Logger } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';
import {
  EmailClassification,
  EmailClassificationContext,
  EmailClassifier,
  EmailToClassify,
} from './email-classifier.interface';

export const ANTHROPIC_CLIENT = 'ANTHROPIC_CLIENT';

@Injectable()
export class LlmEmailClassifier implements EmailClassifier {
  private readonly logger = new Logger(LlmEmailClassifier.name);

  constructor(private readonly client: Anthropic) {}

  async classify(email: EmailToClassify, context: EmailClassificationContext): Promise<EmailClassification> {
    const tom = context.tomPreferido === 'LEVEMENTE_EXPLICATIVO' ? 'levemente mais explicativo' : 'direto e curto';
    try {
      const response = await this.client.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 200,
        messages: [
          {
            role: 'user',
            content:
              `Classifique este e-mail como PRECISA_ATENCAO ou PODE_ESPERAR, e escreva um resumo de ` +
              `1 frase curta no tom ${tom}. Responda apenas com um JSON no formato ` +
              `{"categoria": "PRECISA_ATENCAO" | "PODE_ESPERAR", "resumoCurto": "..."}, sem texto extra.\n\n` +
              `De: ${email.remetente}\nAssunto: ${email.assunto}\nTrecho: ${email.corpo}`,
          },
        ],
      });
      const block = response.content[0];
      const text = block.type === 'text' ? block.text : '';
      const parsed = JSON.parse(text) as { categoria?: string; resumoCurto?: string };
      return {
        categoria: parsed.categoria === 'PRECISA_ATENCAO' ? 'PRECISA_ATENCAO' : 'PODE_ESPERAR',
        resumoCurto: parsed.resumoCurto ?? email.assunto,
      };
    } catch (error) {
      this.logger.warn(`LLM classification failed, falling back to PODE_ESPERAR: ${error}`);
      return { categoria: 'PODE_ESPERAR', resumoCurto: email.assunto };
    }
  }
}
```

`backend/src/email-classification/email-classification.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';
import { HeuristicEmailClassifier } from './heuristic-email-classifier.service';
import { LlmEmailClassifier, ANTHROPIC_CLIENT } from './llm-email-classifier.service';

@Module({
  providers: [
    HeuristicEmailClassifier,
    {
      provide: ANTHROPIC_CLIENT,
      useFactory: () => new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY }),
    },
    {
      provide: LlmEmailClassifier,
      useFactory: (client: Anthropic) => new LlmEmailClassifier(client),
      inject: [ANTHROPIC_CLIENT],
    },
  ],
  exports: [HeuristicEmailClassifier, LlmEmailClassifier],
})
export class EmailClassificationModule {}
```

- [ ] **Step 9: Run test to verify it passes**

```bash
npx jest src/email-classification/llm-email-classifier.service.spec.ts
```
Expected: PASS, 3 tests.

- [ ] **Step 10: Commit**

```bash
git add backend/src/email-classification backend/package.json backend/package-lock.json
git commit -m "feat: add pluggable heuristic and LLM email classifiers"
```

---

### Task 5: Email sync service and summary read endpoint

**Files:**
- Create: `backend/src/email-sync/email-sync.service.ts`
- Create: `backend/src/email-sync/email-summary.controller.ts`
- Create: `backend/src/email-sync/email-sync.module.ts`
- Test: `backend/src/email-sync/email-sync.service.spec.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Consumes: `GmailApiClient`, `GmailConnectionsService` (Task 3), `HeuristicEmailClassifier`, `LlmEmailClassifier` (Task 4), `SensoryProfileService.get` (Fase 1), `UsersService.getByFirebaseUidOrThrow` (Fase 1), `PrismaService`.
- Produces: `EmailSyncService.syncUser(userId: string): Promise<{ novosPrecisamAtencao: number }>` (consumed by Task 6's scheduler), `EmailSyncService.list(firebaseUid: string): Promise<EmailSummary[]>`. Route: `GET /resumos-email`.

- [ ] **Step 1: Write the failing service test**

`backend/src/email-sync/email-sync.service.spec.ts`:
```typescript
import { EmailSyncService } from './email-sync.service';

function buildDeps() {
  const prisma = {
    gmailConnection: { findUnique: jest.fn(), update: jest.fn() },
    user: { findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', plano: 'simples' }) },
    emailSummary: { findUnique: jest.fn().mockResolvedValue(null), create: jest.fn(), findMany: jest.fn() },
  };
  const gmailApiClient = { fetchInitialUnread: jest.fn(), fetchIncremental: jest.fn() };
  const connectionsService = { getDecryptedRefreshToken: jest.fn().mockResolvedValue('rt-123') };
  const sensoryProfileService = { get: jest.fn().mockResolvedValue(null) };
  const heuristicClassifier = { classify: jest.fn().mockResolvedValue({ categoria: 'PODE_ESPERAR', resumoCurto: 'ok' }) };
  const llmClassifier = { classify: jest.fn().mockResolvedValue({ categoria: 'PRECISA_ATENCAO', resumoCurto: 'llm ok' }) };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1', firebaseUid: 'fb1' }) };

  return { prisma, gmailApiClient, connectionsService, sensoryProfileService, heuristicClassifier, llmClassifier, usersService };
}

function buildService(deps: ReturnType<typeof buildDeps>) {
  return new EmailSyncService(
    deps.prisma as any,
    deps.gmailApiClient as any,
    deps.connectionsService as any,
    deps.sensoryProfileService as any,
    deps.heuristicClassifier as any,
    deps.llmClassifier as any,
    deps.usersService as any,
  );
}

describe('EmailSyncService', () => {
  it('returns zero and does nothing when the user has no Gmail connection', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue(null);
    const service = buildService(deps);

    const result = await service.syncUser('u1');

    expect(result).toEqual({ novosPrecisamAtencao: 0 });
    expect(deps.gmailApiClient.fetchInitialUnread).not.toHaveBeenCalled();
  });

  it('performs a full initial sync when there is no lastHistoryId yet', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [{ gmailMessageId: 'm1', remetente: 'x@example.com', assunto: 'Assunto', corpo: 'corpo', recebidoEm: new Date() }],
      historyId: 'h1',
    });
    const service = buildService(deps);

    const result = await service.syncUser('u1');

    expect(deps.gmailApiClient.fetchInitialUnread).toHaveBeenCalledWith('rt-123');
    expect(deps.heuristicClassifier.classify).toHaveBeenCalled();
    expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ userId: 'u1', gmailMessageId: 'm1' }) }),
    );
    expect(deps.prisma.gmailConnection.update).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      data: { lastHistoryId: 'h1', ultimaSincronizacao: expect.any(Date) },
    });
    expect(result.novosPrecisamAtencao).toBe(0);
  });

  it('performs an incremental sync when a lastHistoryId is stored', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'h1' });
    deps.gmailApiClient.fetchIncremental.mockResolvedValue({
      emails: [{ gmailMessageId: 'm2', remetente: 'x@example.com', assunto: 'Novo', corpo: '', recebidoEm: new Date() }],
      historyId: 'h2',
      historyExpired: false,
    });
    const service = buildService(deps);

    await service.syncUser('u1');

    expect(deps.gmailApiClient.fetchIncremental).toHaveBeenCalledWith('rt-123', 'h1');
    expect(deps.gmailApiClient.fetchInitialUnread).not.toHaveBeenCalled();
  });

  it('falls back to a full sync when the stored historyId has expired', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: 'stale' });
    deps.gmailApiClient.fetchIncremental.mockResolvedValue({ emails: [], historyId: null, historyExpired: true });
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({ emails: [], historyId: 'h-fresh' });
    const service = buildService(deps);

    await service.syncUser('u1');

    expect(deps.gmailApiClient.fetchInitialUnread).toHaveBeenCalledWith('rt-123');
  });

  it('skips messages that were already synced (deduplication)', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.prisma.emailSummary.findUnique.mockResolvedValue({ id: 'existing' });
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [{ gmailMessageId: 'already-there', remetente: 'x@example.com', assunto: 'A', corpo: '', recebidoEm: new Date() }],
      historyId: 'h1',
    });
    const service = buildService(deps);

    await service.syncUser('u1');

    expect(deps.prisma.emailSummary.create).not.toHaveBeenCalled();
  });

  it('uses the LLM classifier when the user is on plano pro', async () => {
    const deps = buildDeps();
    deps.prisma.user.findUniqueOrThrow.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', plano: 'pro' });
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [{ gmailMessageId: 'm1', remetente: 'x@example.com', assunto: 'A', corpo: '', recebidoEm: new Date() }],
      historyId: 'h1',
    });
    const service = buildService(deps);

    const result = await service.syncUser('u1');

    expect(deps.llmClassifier.classify).toHaveBeenCalled();
    expect(deps.heuristicClassifier.classify).not.toHaveBeenCalled();
    expect(result.novosPrecisamAtencao).toBe(1);
  });

  it('falls back to PODE_ESPERAR when the classifier itself throws', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.heuristicClassifier.classify.mockRejectedValue(new Error('boom'));
    deps.gmailApiClient.fetchInitialUnread.mockResolvedValue({
      emails: [{ gmailMessageId: 'm1', remetente: 'x@example.com', assunto: 'Assunto original', corpo: '', recebidoEm: new Date() }],
      historyId: 'h1',
    });
    const service = buildService(deps);

    await service.syncUser('u1');

    expect(deps.prisma.emailSummary.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ categoria: 'PODE_ESPERAR', resumoCurto: 'Assunto original' }),
      }),
    );
  });

  it('lists summaries scoped to the resolved user, most recent first', async () => {
    const deps = buildDeps();
    deps.prisma.emailSummary.findMany.mockResolvedValue([]);
    const service = buildService(deps);

    await service.list('fb1');

    expect(deps.prisma.emailSummary.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      orderBy: { recebidoEm: 'desc' },
    });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
npx jest src/email-sync/email-sync.service.spec.ts
```
Expected: FAIL — `Cannot find module './email-sync.service'`.

- [ ] **Step 3: Implement EmailSyncService, controller, module**

`backend/src/email-sync/email-sync.service.ts`:
```typescript
import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { GmailApiClient } from '../gmail/gmail-api-client.service';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';
import { SensoryProfileService } from '../sensory-profile/sensory-profile.service';
import { HeuristicEmailClassifier } from '../email-classification/heuristic-email-classifier.service';
import { LlmEmailClassifier } from '../email-classification/llm-email-classifier.service';
import { EmailClassifier } from '../email-classification/email-classifier.interface';
import { UsersService } from '../users/users.service';

@Injectable()
export class EmailSyncService {
  private readonly logger = new Logger(EmailSyncService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly gmailApiClient: GmailApiClient,
    private readonly connectionsService: GmailConnectionsService,
    private readonly sensoryProfileService: SensoryProfileService,
    private readonly heuristicClassifier: HeuristicEmailClassifier,
    private readonly llmClassifier: LlmEmailClassifier,
    private readonly usersService: UsersService,
  ) {}

  async syncUser(userId: string): Promise<{ novosPrecisamAtencao: number }> {
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId } });
    if (!connection) return { novosPrecisamAtencao: 0 };

    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(userId);
    if (!refreshToken) return { novosPrecisamAtencao: 0 };

    const { emails, historyId } = await this.fetchNewEmails(refreshToken, connection.lastHistoryId);

    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    const classifier: EmailClassifier = user.plano === 'pro' ? this.llmClassifier : this.heuristicClassifier;
    const sensoryProfile = await this.sensoryProfileService.get(user.firebaseUid);
    const tomPreferido = (sensoryProfile?.dados as { tomPreferido?: string } | undefined)?.tomPreferido;

    let novosPrecisamAtencao = 0;
    for (const email of emails) {
      const alreadySynced = await this.prisma.emailSummary.findUnique({
        where: { userId_gmailMessageId: { userId, gmailMessageId: email.gmailMessageId } },
      });
      if (alreadySynced) continue;

      let classification;
      try {
        classification = await classifier.classify(
          { remetente: email.remetente, assunto: email.assunto, corpo: email.corpo },
          { tomPreferido },
        );
      } catch (error) {
        this.logger.error(`Classification failed for message ${email.gmailMessageId}`, error as Error);
        classification = { categoria: 'PODE_ESPERAR' as const, resumoCurto: email.assunto };
      }

      await this.prisma.emailSummary.create({
        data: {
          userId,
          gmailMessageId: email.gmailMessageId,
          remetente: email.remetente,
          assunto: email.assunto,
          resumoCurto: classification.resumoCurto,
          categoria: classification.categoria,
          recebidoEm: email.recebidoEm,
        },
      });

      if (classification.categoria === 'PRECISA_ATENCAO') novosPrecisamAtencao++;
    }

    await this.prisma.gmailConnection.update({
      where: { userId },
      data: { lastHistoryId: historyId, ultimaSincronizacao: new Date() },
    });

    return { novosPrecisamAtencao };
  }

  private async fetchNewEmails(refreshToken: string, lastHistoryId: string | null) {
    if (!lastHistoryId) {
      return this.gmailApiClient.fetchInitialUnread(refreshToken);
    }

    const incremental = await this.gmailApiClient.fetchIncremental(refreshToken, lastHistoryId);
    if (!incremental.historyExpired) {
      return { emails: incremental.emails, historyId: incremental.historyId };
    }

    this.logger.warn(`historyId expired, falling back to a full sync`);
    return this.gmailApiClient.fetchInitialUnread(refreshToken);
  }

  async list(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.emailSummary.findMany({
      where: { userId: user.id },
      orderBy: { recebidoEm: 'desc' },
    });
  }
}
```

`backend/src/email-sync/email-summary.controller.ts`:
```typescript
import { Controller, Get, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { EmailSyncService } from './email-sync.service';

@UseGuards(FirebaseAuthGuard)
@Controller('resumos-email')
export class EmailSummaryController {
  constructor(private readonly emailSyncService: EmailSyncService) {}

  @Get()
  async list(@CurrentFirebaseUid() firebaseUid: string) {
    return this.emailSyncService.list(firebaseUid);
  }
}
```

`backend/src/email-sync/email-sync.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { GmailModule } from '../gmail/gmail.module';
import { SensoryProfileModule } from '../sensory-profile/sensory-profile.module';
import { EmailClassificationModule } from '../email-classification/email-classification.module';
import { UsersModule } from '../users/users.module';
import { EmailSyncService } from './email-sync.service';
import { EmailSummaryController } from './email-summary.controller';

@Module({
  imports: [GmailModule, SensoryProfileModule, EmailClassificationModule, UsersModule],
  providers: [EmailSyncService],
  controllers: [EmailSummaryController],
  exports: [EmailSyncService],
})
export class EmailSyncModule {}
```

Modify `backend/src/app.module.ts` to add `EmailSyncModule` to `imports` (after `GmailModule`, preserving everything else):
```typescript
import { EmailSyncModule } from './email-sync/email-sync.module';

@Module({
  imports: [
    PrismaModule,
    AuthModule,
    UsersModule,
    SensoryProfileModule,
    TrustedContactsModule,
    EmergencyModule,
    GmailModule,
    EmailSyncModule,
  ],
})
export class AppModule {}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
npx jest src/email-sync/email-sync.service.spec.ts
```
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/email-sync backend/src/app.module.ts
git commit -m "feat: add email sync orchestration service and resumos-email read endpoint"
```

---

### Task 6: Background scheduler and push notifications

**Files:**
- Create: `backend/src/email-sync/email-sync.scheduler.ts`
- Create: `backend/src/notifications/notification.service.ts`
- Create: `backend/src/notifications/notifications.module.ts`
- Create: `backend/src/users/dto/register-fcm-token.dto.ts`
- Test: `backend/src/email-sync/email-sync.scheduler.spec.ts`
- Test: `backend/src/notifications/notification.service.spec.ts`
- Test: `backend/src/users/users.service.spec.ts` (extend)
- Modify: `backend/src/email-sync/email-sync.module.ts`
- Modify: `backend/src/users/users.service.ts`
- Modify: `backend/src/users/users.controller.ts`
- Modify: `backend/src/app.module.ts`
- Modify: `backend/package.json` (add `@nestjs/schedule`)

**Interfaces:**
- Consumes: `EmailSyncService.syncUser` (Task 5), `FIREBASE_ADMIN` (Fase 1), `SensoryProfileService.get` (Fase 1), `PrismaService`.
- Produces: `NotificationService.notifyNewEmailsNeedAttention(userId, count): Promise<void>`, `EmailSyncScheduler` (runs every 20 minutes via `@Cron`), `UsersService.registerFcmToken(firebaseUid, fcmToken): Promise<void>`. Route: `POST /users/me/fcm-token`.

- [ ] **Step 1: Install `@nestjs/schedule` and register it globally**

```bash
cd backend
npm install @nestjs/schedule
```

Modify `backend/src/app.module.ts` to add `ScheduleModule.forRoot()`:
```typescript
import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { SensoryProfileModule } from './sensory-profile/sensory-profile.module';
import { TrustedContactsModule } from './trusted-contacts/trusted-contacts.module';
import { EmergencyModule } from './emergency/emergency.module';
import { GmailModule } from './gmail/gmail.module';
import { EmailSyncModule } from './email-sync/email-sync.module';

@Module({
  imports: [
    ScheduleModule.forRoot(),
    PrismaModule,
    AuthModule,
    UsersModule,
    SensoryProfileModule,
    TrustedContactsModule,
    EmergencyModule,
    GmailModule,
    EmailSyncModule,
  ],
})
export class AppModule {}
```

- [ ] **Step 2: Write the failing NotificationService test**

`backend/src/notifications/notification.service.spec.ts`:
```typescript
import { NotificationService } from './notification.service';

function buildDeps() {
  const send = jest.fn().mockResolvedValue('message-id');
  const firebaseAdmin = { messaging: () => ({ send }) };
  const prisma = { user: { findUnique: jest.fn() } };
  const sensoryProfileService = { get: jest.fn() };
  return { firebaseAdmin, prisma, sensoryProfileService, send };
}

describe('NotificationService', () => {
  it('sends an aggregated notification when toleranciaNotificacao is PADRAO', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'PADRAO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 3);

    expect(send).toHaveBeenCalledWith({
      token: 'token-abc',
      notification: { title: 'Sincro', body: '3 e-mails precisam da sua atenção' },
    });
  });

  it('uses singular phrasing for exactly one email', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'PADRAO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 1);

    expect(send).toHaveBeenCalledWith(
      expect.objectContaining({ notification: expect.objectContaining({ body: '1 e-mail precisa da sua atenção' }) }),
    );
  });

  it('does not send when toleranciaNotificacao is SILENCIOSAS', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'SILENCIOSAS' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 3);

    expect(send).not.toHaveBeenCalled();
  });

  it('does not send when toleranciaNotificacao is HORARIO_ESPECIFICO (no time window is stored yet)', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'HORARIO_ESPECIFICO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 3);

    expect(send).not.toHaveBeenCalled();
  });

  it('does not send when the user has no fcmToken registered', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: null });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyNewEmailsNeedAttention('u1', 3);

    expect(send).not.toHaveBeenCalled();
    expect(sensoryProfileService.get).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

```bash
npx jest src/notifications/notification.service.spec.ts
```
Expected: FAIL — `Cannot find module './notification.service'`.

- [ ] **Step 4: Implement NotificationService and module**

`backend/src/notifications/notification.service.ts`:
```typescript
import { Inject, Injectable } from '@nestjs/common';
import * as admin from 'firebase-admin';
import { FIREBASE_ADMIN } from '../auth/firebase-admin.provider';
import { PrismaService } from '../prisma/prisma.service';
import { SensoryProfileService } from '../sensory-profile/sensory-profile.service';

@Injectable()
export class NotificationService {
  constructor(
    @Inject(FIREBASE_ADMIN) private readonly firebaseAdmin: typeof admin,
    private readonly prisma: PrismaService,
    private readonly sensoryProfileService: SensoryProfileService,
  ) {}

  async notifyNewEmailsNeedAttention(userId: string, count: number): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user?.fcmToken) return;

    const sensoryProfile = await this.sensoryProfileService.get(user.firebaseUid);
    const tolerancia = (sensoryProfile?.dados as { toleranciaNotificacao?: string } | undefined)?.toleranciaNotificacao;

    // 'HORARIO_ESPECIFICO' não empurra notificação: a anamnese da Fase 1 nunca coletou a faixa
    // de horário real (só a categoria), então não há como saber se agora está dentro da janela
    // que o usuário pediu — até essa lacuna ser resolvida, tratamos como silencioso por segurança.
    if (tolerancia !== 'PADRAO') return;

    await this.firebaseAdmin.messaging().send({
      token: user.fcmToken,
      notification: {
        title: 'Sincro',
        body: count === 1 ? '1 e-mail precisa da sua atenção' : `${count} e-mails precisam da sua atenção`,
      },
    });
  }
}
```

`backend/src/notifications/notifications.module.ts`:
```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { SensoryProfileModule } from '../sensory-profile/sensory-profile.module';
import { NotificationService } from './notification.service';

@Module({
  imports: [AuthModule, SensoryProfileModule],
  providers: [NotificationService],
  exports: [NotificationService],
})
export class NotificationsModule {}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
npx jest src/notifications/notification.service.spec.ts
```
Expected: PASS, 5 tests.

- [ ] **Step 6: Write the failing scheduler test**

`backend/src/email-sync/email-sync.scheduler.spec.ts`:
```typescript
import { EmailSyncScheduler } from './email-sync.scheduler';

describe('EmailSyncScheduler', () => {
  it('syncs every connected user and notifies when there are new attention-needing emails', async () => {
    const prisma = {
      gmailConnection: { findMany: jest.fn().mockResolvedValue([{ userId: 'u1' }, { userId: 'u2' }]) },
    };
    const emailSyncService = {
      syncUser: jest.fn().mockResolvedValueOnce({ novosPrecisamAtencao: 2 }).mockResolvedValueOnce({ novosPrecisamAtencao: 0 }),
    };
    const notificationService = { notifyNewEmailsNeedAttention: jest.fn() };
    const scheduler = new EmailSyncScheduler(prisma as any, emailSyncService as any, notificationService as any);

    await scheduler.syncAllConnectedUsers();

    expect(emailSyncService.syncUser).toHaveBeenNthCalledWith(1, 'u1');
    expect(emailSyncService.syncUser).toHaveBeenNthCalledWith(2, 'u2');
    expect(notificationService.notifyNewEmailsNeedAttention).toHaveBeenCalledTimes(1);
    expect(notificationService.notifyNewEmailsNeedAttention).toHaveBeenCalledWith('u1', 2);
  });

  it('keeps syncing remaining users when one user sync throws', async () => {
    const prisma = { gmailConnection: { findMany: jest.fn().mockResolvedValue([{ userId: 'u1' }, { userId: 'u2' }]) } };
    const emailSyncService = {
      syncUser: jest.fn().mockRejectedValueOnce(new Error('boom')).mockResolvedValueOnce({ novosPrecisamAtencao: 1 }),
    };
    const notificationService = { notifyNewEmailsNeedAttention: jest.fn() };
    const scheduler = new EmailSyncScheduler(prisma as any, emailSyncService as any, notificationService as any);

    await scheduler.syncAllConnectedUsers();

    expect(emailSyncService.syncUser).toHaveBeenCalledTimes(2);
    expect(notificationService.notifyNewEmailsNeedAttention).toHaveBeenCalledWith('u2', 1);
  });
});
```

- [ ] **Step 7: Run test to verify it fails**

```bash
npx jest src/email-sync/email-sync.scheduler.spec.ts
```
Expected: FAIL — `Cannot find module './email-sync.scheduler'`.

- [ ] **Step 8: Implement EmailSyncScheduler**

`backend/src/email-sync/email-sync.scheduler.ts`:
```typescript
import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { EmailSyncService } from './email-sync.service';
import { NotificationService } from '../notifications/notification.service';

@Injectable()
export class EmailSyncScheduler {
  private readonly logger = new Logger(EmailSyncScheduler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly emailSyncService: EmailSyncService,
    private readonly notificationService: NotificationService,
  ) {}

  @Cron('*/20 * * * *')
  async syncAllConnectedUsers(): Promise<void> {
    const connections = await this.prisma.gmailConnection.findMany({ select: { userId: true } });
    for (const { userId } of connections) {
      try {
        const { novosPrecisamAtencao } = await this.emailSyncService.syncUser(userId);
        if (novosPrecisamAtencao > 0) {
          await this.notificationService.notifyNewEmailsNeedAttention(userId, novosPrecisamAtencao);
        }
      } catch (error) {
        this.logger.error(`Failed to sync Gmail for user ${userId}`, error as Error);
      }
    }
  }
}
```

Modify `backend/src/email-sync/email-sync.module.ts` to wire the scheduler and notifications module:
```typescript
import { Module } from '@nestjs/common';
import { GmailModule } from '../gmail/gmail.module';
import { SensoryProfileModule } from '../sensory-profile/sensory-profile.module';
import { EmailClassificationModule } from '../email-classification/email-classification.module';
import { UsersModule } from '../users/users.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { EmailSyncService } from './email-sync.service';
import { EmailSyncScheduler } from './email-sync.scheduler';
import { EmailSummaryController } from './email-summary.controller';

@Module({
  imports: [GmailModule, SensoryProfileModule, EmailClassificationModule, UsersModule, NotificationsModule],
  providers: [EmailSyncService, EmailSyncScheduler],
  controllers: [EmailSummaryController],
  exports: [EmailSyncService],
})
export class EmailSyncModule {}
```

- [ ] **Step 9: Run test to verify it passes**

```bash
npx jest src/email-sync/email-sync.scheduler.spec.ts
```
Expected: PASS, 2 tests.

- [ ] **Step 10: Write the failing FCM token registration test**

Extend `backend/src/users/users.service.spec.ts` — add this test to the existing `describe('UsersService', ...)` block (do not remove the existing 3 tests):
```typescript
  it('registers an fcm token for the resolved user', async () => {
    const prisma = buildPrismaMock();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1' });
    prisma.user.update = jest.fn();
    const service = new UsersService(prisma as any);

    await service.registerFcmToken('fb1', 'token-xyz');

    expect(prisma.user.update).toHaveBeenCalledWith({ where: { id: 'u1' }, data: { fcmToken: 'token-xyz' } });
  });
```

- [ ] **Step 11: Run test to verify it fails**

```bash
npx jest src/users/users.service.spec.ts
```
Expected: FAIL — `service.registerFcmToken is not a function`.

- [ ] **Step 12: Implement UsersService.registerFcmToken and the endpoint**

Modify `backend/src/users/users.service.ts`, add this method to the `UsersService` class (keep every existing method):
```typescript
  async registerFcmToken(firebaseUid: string, fcmToken: string): Promise<void> {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);
    await this.prisma.user.update({ where: { id: user.id }, data: { fcmToken } });
  }
```

`backend/src/users/dto/register-fcm-token.dto.ts`:
```typescript
import { IsString, MinLength } from 'class-validator';

export class RegisterFcmTokenDto {
  @IsString()
  @MinLength(1)
  fcmToken: string;
}
```

Modify `backend/src/users/users.controller.ts` to add the route (keep the existing `POST /users/me` and `GET /users/me` routes exactly as they are):
```typescript
import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from './users.service';
import { UpsertUserDto } from './dto/upsert-user.dto';
import { RegisterFcmTokenDto } from './dto/register-fcm-token.dto';

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

  @Post('me/fcm-token')
  async registerFcmToken(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: RegisterFcmTokenDto) {
    await this.usersService.registerFcmToken(firebaseUid, dto.fcmToken);
    return { success: true };
  }
}
```

- [ ] **Step 13: Run test to verify it passes**

```bash
npx jest src/users/users.service.spec.ts
```
Expected: PASS, 4 tests.

- [ ] **Step 14: Full backend test suite + boot check**

```bash
npm test
npm run start:dev
```
Expected: all tests pass, app boots cleanly (the `@Cron` job registers but won't fire meaningfully without a real `TOKEN_ENCRYPTION_KEY`/Google credentials populated — that's fine, it'll just find zero connections and no-op). Stop with Ctrl+C.

- [ ] **Step 15: Commit**

```bash
git add backend/src/email-sync backend/src/notifications backend/src/users backend/src/app.module.ts backend/package.json backend/package-lock.json
git commit -m "feat: add background Gmail sync scheduler and aggregated push notifications"
```

---

### Task 7: Backend e2e test for the full email triage flow

**Files:**
- Create: `backend/test/email-triage-flow.e2e-spec.ts`
- Create: `backend/test/support/fake-gmail-oauth.ts`
- Create: `backend/test/support/fake-gmail-api-client.ts`
- Modify: `backend/test/support/fake-firebase-admin.ts`

**Interfaces:**
- Consumes: `AppModule` (all modules through Task 6), `GmailOAuthService`/`GmailApiClient` DI tokens (Task 3), `FIREBASE_ADMIN` (Fase 1).
- Produces: a repeatable e2e test proving: connect Gmail → sync → summaries appear via `GET /resumos-email` (never exposing email bodies) → disconnect wipes everything, all correctly scoped by `firebaseUid`.

- [ ] **Step 1: Extend the fake Firebase Admin to support messaging**

Modify `backend/test/support/fake-firebase-admin.ts` — add a `messaging()` method to the object it returns (keep the existing `auth()` method exactly as-is):
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
    messaging: () => ({
      send: async () => 'fake-message-id',
    }),
  };
}
```

- [ ] **Step 2: Write the fake Gmail OAuth and API client test doubles**

`backend/test/support/fake-gmail-oauth.ts`:
```typescript
export function buildFakeGmailOAuth() {
  return {
    exchangeServerAuthCode: async (code: string) => ({ refreshToken: `fake-refresh-token-for-${code}` }),
    authenticatedClientFor: () => ({}),
    getEmailAddress: async () => 'usuario.teste@gmail.com',
    revoke: async () => undefined,
  };
}
```

`backend/test/support/fake-gmail-api-client.ts`:
```typescript
export function buildFakeGmailApiClient() {
  return {
    fetchInitialUnread: async () => ({
      emails: [
        {
          gmailMessageId: 'msg-urgente',
          remetente: 'Banco Exemplo <contato@banco.example>',
          assunto: 'Fatura com vencimento urgente',
          corpo: 'Sua fatura vence em breve.',
          recebidoEm: new Date(),
        },
        {
          gmailMessageId: 'msg-newsletter',
          remetente: 'Newsletter <news@example.com>',
          assunto: 'Novidades da semana',
          corpo: 'Confira as novidades.',
          recebidoEm: new Date(),
        },
      ],
      historyId: 'history-1',
    }),
    fetchIncremental: async () => ({ emails: [], historyId: 'history-1', historyExpired: false }),
  };
}
```

- [ ] **Step 3: Write the failing e2e test**

`backend/test/email-triage-flow.e2e-spec.ts`:
```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import * as request from 'supertest';
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
  let app: INestApplication;
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
```

- [ ] **Step 4: Run test to verify it fails first, then passes**

```bash
cd backend
docker ps  # confirm Postgres is up
npx jest --config ./test/jest-e2e.json email-triage-flow
```
Expected on first run before this task's code exists: FAIL. After Steps 1-3 above are in place: PASS, 2 tests. This test uses `plano: 'simples'` (the DB default — nothing in the test sets it to `'pro'`), so it exercises the real `HeuristicEmailClassifier` and never calls the Anthropic API — no `ANTHROPIC_API_KEY` needed for this test to pass, even though it's set in `.env`.

- [ ] **Step 5: Run the full test suite once more to confirm no regressions**

```bash
npm test
npm run test:e2e
```
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add backend/test
git commit -m "test: add e2e coverage for the full Gmail connect, sync, and disconnect flow"
```

---

## Mobile (Flutter)

### Task 8: Gmail connection (mobile)

**Files:**
- Create: `mobile/lib/features/email_triage/gmail_connection_repository.dart`
- Create: `mobile/lib/features/email_triage/email_triage_providers.dart`
- Modify: `mobile/lib/features/home/home_screen.dart`
- Modify: `mobile/lib/features/settings/settings_screen.dart`
- Test: `mobile/test/features/email_triage/gmail_connection_repository_test.dart`
- Modify: `mobile/pubspec.yaml` (add `google_sign_in`)

**Interfaces:**
- Consumes: `apiClientProvider` (Fase 1 Task 10).
- Produces: `GmailConnectionStatus` model, `GmailConnectionRepository.connect()`, `.status()`, `.disconnect()`, `gmailConnectionStatusProvider` (Riverpod `FutureProvider.autoDispose`). Consumed by Task 9's Home card and inbox screen.

**⚠️ Requires Prerequisites item 3** (the Web OAuth Client ID from Task 3) — you'll pass it as `GOOGLE_WEB_CLIENT_ID` via `--dart-define` when running/testing the app for real; it's not needed for the unit tests in this task, which mock `GoogleSignIn` entirely.

- [ ] **Step 1: Add the google_sign_in package**

```bash
cd mobile
flutter pub add google_sign_in
```

- [ ] **Step 2: Write the failing repository test**

`mobile/test/features/email_triage/gmail_connection_repository_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

void main() {
  test('connect signs in with Google and posts the serverAuthCode', () async {
    final mockGoogleSignIn = MockGoogleSignIn();
    final mockAccount = MockGoogleSignInAccount();
    when(() => mockAccount.serverAuthCode).thenReturn('auth-code-123');
    when(() => mockGoogleSignIn.signIn()).thenAnswer((_) async => mockAccount);

    String? capturedPath;
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'success': true}));
    }));

    final repository = GmailConnectionRepository(dio, mockGoogleSignIn);
    await repository.connect();

    expect(capturedPath, '/gmail/connect');
    expect(capturedData, {'serverAuthCode': 'auth-code-123'});
  });

  test('connect throws when the user cancels the Google sign-in', () async {
    final mockGoogleSignIn = MockGoogleSignIn();
    when(() => mockGoogleSignIn.signIn()).thenAnswer((_) async => null);
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));

    final repository = GmailConnectionRepository(dio, mockGoogleSignIn);

    expect(() => repository.connect(), throwsException);
  });

  test('status parses the connection response', () async {
    final mockGoogleSignIn = MockGoogleSignIn();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'connected': true, 'gmailEmail': 'ana@example.com'},
      ));
    }));

    final repository = GmailConnectionRepository(dio, mockGoogleSignIn);
    final status = await repository.status();

    expect(status.connected, true);
    expect(status.gmailEmail, 'ana@example.com');
  });

  test('disconnect calls the delete endpoint and signs out of Google', () async {
    final mockGoogleSignIn = MockGoogleSignIn();
    when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));

    final repository = GmailConnectionRepository(dio, mockGoogleSignIn);
    await repository.disconnect();

    expect(capturedPath, '/gmail/connection');
    verify(() => mockGoogleSignIn.signOut()).called(1);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd mobile
flutter test test/features/email_triage/gmail_connection_repository_test.dart
```
Expected: FAIL — module not found.

- [ ] **Step 4: Implement GmailConnectionRepository and providers**

`mobile/lib/features/email_triage/gmail_connection_repository.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GmailConnectionStatus {
  const GmailConnectionStatus({required this.connected, this.gmailEmail});

  final bool connected;
  final String? gmailEmail;

  factory GmailConnectionStatus.fromJson(Map<String, dynamic> json) {
    return GmailConnectionStatus(
      connected: json['connected'] as bool,
      gmailEmail: json['gmailEmail'] as String?,
    );
  }
}

class GmailConnectionRepository {
  GmailConnectionRepository(this._dio, this._googleSignIn);

  final Dio _dio;
  final GoogleSignIn _googleSignIn;

  Future<void> connect() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('Login com Google cancelado.');
    }
    final serverAuthCode = account.serverAuthCode;
    if (serverAuthCode == null) {
      throw Exception('Não foi possível obter autorização do Google para acessar o Gmail.');
    }
    await _dio.post('/gmail/connect', data: {'serverAuthCode': serverAuthCode});
  }

  Future<GmailConnectionStatus> status() async {
    final response = await _dio.get('/gmail/connection');
    return GmailConnectionStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> disconnect() async {
    await _dio.delete('/gmail/connection');
    await _googleSignIn.signOut();
  }
}
```

`mobile/lib/features/email_triage/email_triage_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/api_providers.dart';
import 'gmail_connection_repository.dart';

const _gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';

const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn(
    scopes: const [_gmailReadonlyScope],
    serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
  );
});

final gmailConnectionRepositoryProvider = Provider<GmailConnectionRepository>((ref) {
  return GmailConnectionRepository(ref.watch(apiClientProvider).dio, ref.watch(googleSignInProvider));
});

final gmailConnectionStatusProvider = FutureProvider.autoDispose<GmailConnectionStatus>((ref) {
  return ref.watch(gmailConnectionRepositoryProvider).status();
});
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/email_triage/gmail_connection_repository_test.dart
```
Expected: PASS, 4 tests.

- [ ] **Step 6: Wire the Home screen card**

Modify `mobile/lib/features/home/home_screen.dart` — replace the static "Finanças e e-mails chegam em breve" text with a Gmail connection card, keeping the existing `EmergencyButton`/contacts-hint logic exactly as-is:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';
import '../email_triage/email_triage_providers.dart';
import 'emergency_button.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(trustedContactsListProvider);
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('🌿 Tudo em ordem por hoje.'),
            const SizedBox(height: 8),
            const Text('Finanças chegam em breve.'),
            const SizedBox(height: 16),
            _GmailCard(statusAsync: gmailStatusAsync),
            const SizedBox(height: 16),
            contactsAsync.when(
              data: (contacts) {
                if (contacts.isEmpty) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _NoContactsHint(),
                      SizedBox(height: 16),
                      EmergencyButton(),
                    ],
                  );
                }
                return const EmergencyButton();
              },
              loading: () => const EmergencyButton(),
              error: (_, __) => const EmergencyButton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _GmailCard extends ConsumerWidget {
  const _GmailCard({required this.statusAsync});

  final AsyncValue statusAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(gmailConnectionRepositoryProvider).connect();
      ref.invalidate(gmailConnectionStatusProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível conectar o Gmail. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('📬 Caixa de Entrada'),
              subtitle: const Text('Conecte seu Gmail para ver um resumo calmo dos seus e-mails.'),
              trailing: ElevatedButton(
                onPressed: () => _connect(context, ref),
                child: const Text('Conectar Gmail'),
              ),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('📬 Caixa de Entrada'),
            subtitle: Text('Conectado como ${status.gmailEmail}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/inbox'),
          ),
        );
      },
      loading: () => const Card(child: ListTile(title: Text('📬 Caixa de Entrada'), subtitle: Text('Carregando...'))),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _NoContactsHint extends StatelessWidget {
  const _NoContactsHint();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          '💡 Adicione um contato de confiança para estar preparado em emergências.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Add a "Desconectar Gmail" option to Settings**

Modify `mobile/lib/features/settings/settings_screen.dart` — add the import and a new method + `ListTile`, keeping every existing method and `ListTile` exactly as they are:
```dart
import '../email_triage/email_triage_providers.dart';
```

Add this method inside `_SettingsScreenState` (alongside `_signOut` etc.):
```dart
  Future<void> _disconnectGmail() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desconectar Gmail?'),
        content: const Text(
          'O resumo da sua caixa de entrada será apagado. Você pode reconectar quando quiser.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(gmailConnectionRepositoryProvider).disconnect();
      ref.invalidate(gmailConnectionStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gmail desconectado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desconectar o Gmail. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

Add this `ListTile` to the `ListView`'s `children`, right after the "Gerenciar contatos de confiança" tile and before the `Divider`:
```dart
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Desconectar Gmail'),
            onTap: _busy ? null : _disconnectGmail,
          ),
```

- [ ] **Step 8: Run the full mobile test suite and analyzer**

```bash
flutter test
flutter analyze
```
Expected: all tests pass, no analyzer issues.

- [ ] **Step 9: Commit**

```bash
git add mobile/lib/features/email_triage mobile/lib/features/home/home_screen.dart mobile/lib/features/settings/settings_screen.dart mobile/test/features/email_triage mobile/pubspec.yaml mobile/pubspec.lock
git commit -m "feat: add Gmail connection flow with Home card and Settings disconnect option"
```

---

### Task 9: Inbox summary screen (mobile)

**Files:**
- Create: `mobile/lib/features/email_triage/email_summary.dart`
- Create: `mobile/lib/features/email_triage/email_summary_repository.dart`
- Create: `mobile/lib/features/email_triage/inbox_screen.dart`
- Modify: `mobile/lib/features/email_triage/email_triage_providers.dart`
- Modify: `mobile/lib/main.dart`
- Test: `mobile/test/features/email_triage/email_summary_repository_test.dart`

**Interfaces:**
- Consumes: `apiClientProvider` (Fase 1 Task 10).
- Produces: `EmailSummary` model, `EmailSummaryRepository.list()`, `emailSummariesProvider` (Riverpod `FutureProvider.autoDispose`). Route `/inbox` registered in `main.dart`, reachable from Task 8's Home card.

- [ ] **Step 1: Write the failing repository test**

`mobile/test/features/email_triage/email_summary_repository_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/email_summary_repository.dart';

void main() {
  test('list parses the array of email summaries', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 's1',
            'remetente': 'Banco <banco@example.com>',
            'assunto': 'Fatura',
            'resumoCurto': 'Fatura vence amanhã',
            'categoria': 'PRECISA_ATENCAO',
            'recebidoEm': '2026-08-02T10:00:00.000Z',
          },
        ],
      ));
    }));
    final repository = EmailSummaryRepository(dio);

    final summaries = await repository.list();

    expect(summaries, hasLength(1));
    expect(summaries.first.assunto, 'Fatura');
    expect(summaries.first.precisaAtencao, true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd mobile
flutter test test/features/email_triage/email_summary_repository_test.dart
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement EmailSummary, repository, providers, screen**

`mobile/lib/features/email_triage/email_summary.dart`:
```dart
class EmailSummary {
  const EmailSummary({
    required this.id,
    required this.remetente,
    required this.assunto,
    required this.resumoCurto,
    required this.categoria,
    required this.recebidoEm,
  });

  final String id;
  final String remetente;
  final String assunto;
  final String resumoCurto;
  final String categoria;
  final DateTime recebidoEm;

  bool get precisaAtencao => categoria == 'PRECISA_ATENCAO';

  factory EmailSummary.fromJson(Map<String, dynamic> json) {
    return EmailSummary(
      id: json['id'] as String,
      remetente: json['remetente'] as String,
      assunto: json['assunto'] as String,
      resumoCurto: json['resumoCurto'] as String,
      categoria: json['categoria'] as String,
      recebidoEm: DateTime.parse(json['recebidoEm'] as String),
    );
  }
}
```

`mobile/lib/features/email_triage/email_summary_repository.dart`:
```dart
import 'package:dio/dio.dart';
import 'email_summary.dart';

class EmailSummaryRepository {
  EmailSummaryRepository(this._dio);

  final Dio _dio;

  Future<List<EmailSummary>> list() async {
    final response = await _dio.get('/resumos-email');
    final data = response.data as List<dynamic>;
    return data.map((json) => EmailSummary.fromJson(json as Map<String, dynamic>)).toList();
  }
}
```

Modify `mobile/lib/features/email_triage/email_triage_providers.dart` — add these imports and providers at the end of the file (keep everything already there from Task 8):
```dart
import 'email_summary.dart';
import 'email_summary_repository.dart';

final emailSummaryRepositoryProvider = Provider<EmailSummaryRepository>((ref) {
  return EmailSummaryRepository(ref.watch(apiClientProvider).dio);
});

final emailSummariesProvider = FutureProvider.autoDispose<List<EmailSummary>>((ref) {
  return ref.watch(emailSummaryRepositoryProvider).list();
});
```

`mobile/lib/features/email_triage/inbox_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'email_summary.dart';
import 'email_triage_providers.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(emailSummariesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Caixa de Entrada')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(emailSummariesProvider),
        child: summariesAsync.when(
          data: (summaries) {
            if (summaries.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhum e-mail novo por aqui. 🌿'),
                  ),
                ],
              );
            }
            final precisamAtencao = summaries.where((s) => s.precisaAtencao).toList();
            final podemEsperar = summaries.where((s) => !s.precisaAtencao).toList();

            return ListView(
              children: [
                if (precisamAtencao.isNotEmpty) ...[
                  const _SectionHeader('Precisam de atenção'),
                  ...precisamAtencao.map((s) => _EmailTile(summary: s)),
                ],
                if (podemEsperar.isNotEmpty) ...[
                  const _SectionHeader('Podem esperar'),
                  ...podemEsperar.map((s) => _EmailTile(summary: s)),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Não foi possível carregar seus e-mails. Puxe para tentar novamente.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _EmailTile extends StatelessWidget {
  const _EmailTile({required this.summary});

  final EmailSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(summary.precisaAtencao ? Icons.priority_high : Icons.check_circle_outline),
      title: Text(summary.assunto),
      subtitle: Text(summary.resumoCurto),
    );
  }
}
```

Modify `mobile/lib/main.dart` — add the import and route (keep every existing route):
```dart
import 'features/email_triage/inbox_screen.dart';
```
```dart
        '/inbox': (_) => const InboxScreen(),
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/email_triage/email_summary_repository_test.dart
```
Expected: PASS, 1 test.

- [ ] **Step 5: Run the full mobile suite and analyzer**

```bash
flutter test
flutter analyze
```
Expected: all pass, no issues.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/email_triage mobile/lib/main.dart mobile/test/features/email_triage
git commit -m "feat: add inbox summary screen grouped by categoria"
```

---

### Task 10: Push notifications (mobile)

**Files:**
- Create: `mobile/lib/features/email_triage/fcm_token_repository.dart`
- Modify: `mobile/lib/features/email_triage/email_triage_providers.dart`
- Modify: `mobile/lib/features/home/home_screen.dart`
- Modify: `mobile/lib/main.dart`
- Test: `mobile/test/features/email_triage/fcm_token_repository_test.dart`
- Modify: `mobile/pubspec.yaml` (add `firebase_messaging`)

**Interfaces:**
- Consumes: `apiClientProvider` (Fase 1 Task 10), `firebase_messaging`'s `FirebaseMessaging.instance`.
- Produces: `FcmTokenRepository.register(fcmToken): Future<void>`. `HomeScreen` registers the device's FCM token once on load; tapping a notification navigates to `/inbox`.

- [ ] **Step 1: Add the firebase_messaging package**

```bash
cd mobile
flutter pub add firebase_messaging
```

- [ ] **Step 2: Write the failing repository test**

`mobile/test/features/email_triage/fcm_token_repository_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/fcm_token_repository.dart';

void main() {
  test('register posts the fcm token', () async {
    String? capturedPath;
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'success': true}));
    }));
    final repository = FcmTokenRepository(dio);

    await repository.register('device-token-abc');

    expect(capturedPath, '/users/me/fcm-token');
    expect(capturedData, {'fcmToken': 'device-token-abc'});
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
flutter test test/features/email_triage/fcm_token_repository_test.dart
```
Expected: FAIL — module not found.

- [ ] **Step 4: Implement FcmTokenRepository**

`mobile/lib/features/email_triage/fcm_token_repository.dart`:
```dart
import 'package:dio/dio.dart';

class FcmTokenRepository {
  FcmTokenRepository(this._dio);

  final Dio _dio;

  Future<void> register(String fcmToken) async {
    await _dio.post('/users/me/fcm-token', data: {'fcmToken': fcmToken});
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/email_triage/fcm_token_repository_test.dart
```
Expected: PASS, 1 test.

- [ ] **Step 6: Add the provider**

Modify `mobile/lib/features/email_triage/email_triage_providers.dart` — add at the end of the file (keep everything already there):
```dart
import 'fcm_token_repository.dart';

final fcmTokenRepositoryProvider = Provider<FcmTokenRepository>((ref) {
  return FcmTokenRepository(ref.watch(apiClientProvider).dio);
});
```

- [ ] **Step 7: Register the token once when the Home screen loads**

Modify `mobile/lib/features/home/home_screen.dart` — convert `HomeScreen` from `ConsumerWidget` to `ConsumerStatefulWidget` so it can register the FCM token once via `initState`, following the same `addPostFrameCallback`-after-build pattern already used by `_RedirectOnce` elsewhere in this codebase. Keep `_GmailCard` and `_NoContactsHint` exactly as Task 8/9 left them; only `HomeScreen` itself changes shape:
```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';
import '../email_triage/email_triage_providers.dart';
import 'emergency_button.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerFcmToken());
  }

  Future<void> _registerFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await ref.read(fcmTokenRepositoryProvider).register(token);
      }
    } catch (_) {
      // Registro de notificação é best-effort: o app continua funcionando
      // normalmente mesmo se o dispositivo não conseguir registrar o token
      // (ex: emulador sem Google Play Services, permissão negada).
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(trustedContactsListProvider);
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('🌿 Tudo em ordem por hoje.'),
            const SizedBox(height: 8),
            const Text('Finanças chegam em breve.'),
            const SizedBox(height: 16),
            _GmailCard(statusAsync: gmailStatusAsync),
            const SizedBox(height: 16),
            contactsAsync.when(
              data: (contacts) {
                if (contacts.isEmpty) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _NoContactsHint(),
                      SizedBox(height: 16),
                      EmergencyButton(),
                    ],
                  );
                }
                return const EmergencyButton();
              },
              loading: () => const EmergencyButton(),
              error: (_, __) => const EmergencyButton(),
            ),
          ],
        ),
      ),
    );
  }
}
```

`_GmailCard` and `_NoContactsHint` stay exactly as they are in the file — only the `HomeScreen`/`_HomeScreenState` classes above change.

- [ ] **Step 8: Handle notification taps navigating to the inbox**

Modify `mobile/lib/main.dart` — add the import and wire a tap handler in `main()`, keeping `Firebase.initializeApp` and the route table exactly as they are:
```dart
import 'package:firebase_messaging/firebase_messaging.dart';
```

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: SincroApp()));
}
```
becomes:
```dart
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onMessageOpenedApp.listen((_) {
    navigatorKey.currentState?.pushNamed('/inbox');
  });
  runApp(const ProviderScope(child: SincroApp()));
}
```

And modify `SincroApp`'s `build` method to attach the key to `MaterialApp`:
```dart
class SincroApp extends StatelessWidget {
  const SincroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Sincro',
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/onboarding-router': (_) => const OnboardingRouterScreen(),
        '/onboarding/anamnese': (_) => const AnamneseWizardScreen(),
        '/onboarding/contacts': (_) => const TrustedContactsScreen(),
        '/home': (_) => const HomeScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/inbox': (_) => const InboxScreen(),
      },
    );
  }
}
```

- [ ] **Step 9: Run the full mobile suite and analyzer**

```bash
flutter test
flutter analyze
```
Expected: all pass, no issues. (`FirebaseMessaging.instance` calls in `_registerFcmToken` won't actually fire in the widget-less repository tests — only `FcmTokenRepository` itself is unit tested; the Home screen's registration call is exercised manually/at runtime, consistent with how Fase 1 didn't widget-test `OnboardingRouterScreen`'s branching either.)

- [ ] **Step 10: Commit**

```bash
git add mobile/lib/features/email_triage mobile/lib/features/home/home_screen.dart mobile/lib/main.dart mobile/test/features/email_triage mobile/pubspec.yaml mobile/pubspec.lock
git commit -m "feat: add FCM push notification registration and notification-tap navigation"
```

---

## Plan Self-Review Notes

- **Spec coverage:** Gmail readonly OAuth connection (Task 3), pluggable heuristic/LLM classification gated by `plano` (Task 4), incremental background sync (Tasks 5-6), aggregated push notifications respecting `toleranciaNotificacao` (Task 6), minimal data retention — no email body ever persisted or even fetched beyond metadata+snippet (Tasks 3, 5), right of deletion on disconnect (Task 3), Home card entry point (Task 8), inbox screen (Task 9), FCM registration (Task 10). All design spec sections have a corresponding task.
- **Known limitation carried from Fase 1, not fixed here (by user decision):** `HORARIO_ESPECIFICO` has no stored time window, so `NotificationService` treats it as silent rather than guessing — documented in Task 6's code comment and this plan's Global Constraints.
- **Type consistency:** `EmailSummary`/`GmailConnectionStatus` field names match between backend response shapes (Tasks 3, 5) and Flutter `fromJson` models (Tasks 8, 9). `EmailClassification.categoria` values (`PRECISA_ATENCAO`/`PODE_ESPERAR`) are identical across `EmailClassifier` implementations (Task 4), `EmailSyncService` (Task 5), and the mobile `EmailSummary.precisaAtencao` getter (Task 9).
- **Deferred:** Outlook/Graph API support, AI-generated reply drafts, calendar/compromisso extraction, and any real billing/checkout for `plano` — all explicitly out of scope per the design spec, left for future iterations of this same pillar.
