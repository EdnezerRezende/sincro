# Gestão Executiva: Rascunhos de Resposta por IA + Agenda Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** For an e-mail classified `PRECISA_ATENCAO`, let the user open it, get 3 AI-generated reply
drafts, edit/send the chosen one for real via Gmail, and — when the sent text contains a promise
with a date/time — confirm a suggested compromisso into a real Google Calendar event with reminders.

**Architecture:** Two new Gmail OAuth scopes (`gmail.send`, `calendar.events`) requested together;
granted-scope flags persisted on `GmailConnection`. Three new backend endpoints under the existing
`resumos-email` route: generate drafts (on open), send + extract commitment (one call), confirm
calendar event (separate, explicit user action). No new database tables — drafts and suggested
commitments are never persisted, and a confirmed event's system of record becomes Google Calendar
itself. Mobile gets one new screen (`EmailDetailScreen`) that walks through draft → edit → send →
confirm, reusing the existing inbox list and connection-status providers.

**Tech Stack:** NestJS + Prisma (backend), Flutter + Riverpod (mobile), `@anthropic-ai/sdk`
(already used for classification), `googleapis` (already used for Gmail, now also for Calendar).

## Global Constraints

- Least-privilege OAuth scopes: `gmail.send` (never `gmail.modify`/`mail.google.com`),
  `calendar.events` (never bare `calendar`).
- Email body (fetched only when generating a draft) and generated drafts/commitments are **never
  persisted** — no database column, no log line, ever contains them.
- The text the user sees/edits is exactly what gets sent — no silent post-processing between the
  "Enviar" tap and the actual Gmail send call.
- A Calendar event is created **only** after an explicit, separate user confirmation — never
  automatically as a side effect of sending.
- Tenant isolation: every new endpoint resolves `user_id` from the verified Firebase token only,
  never from a client-supplied parameter — same pattern as the rest of the backend.
- `temEscopoEnvio`/`temEscopoAgenda` gate each capability independently — a user can have one
  without the other, and both frontend and backend must respect that independently.
- No Outlook support, no plan (`simples`/`pro`) differentiation, no HTML/attachments in the sent
  reply, no more than one compromisso per sent reply, no extraction from the *received* email —
  only from the *sent* reply text.

---

## File Structure

| File | Change |
|---|---|
| `backend/prisma/schema.prisma` | **Modify.** `GmailConnection` gains `temEscopoEnvio`/`temEscopoAgenda`. |
| `backend/src/gmail/gmail-oauth.service.ts` | **Modify.** `exchangeServerAuthCode` also returns the granted `scope` string. |
| `backend/src/gmail/gmail-connections.service.ts` | **Modify.** Persists/exposes the two scope flags; new `getConnectionOrThrow`. |
| `backend/test/support/fake-gmail-oauth.ts` | **Modify.** Fake returns a configurable `scope`. |
| `backend/test/email-triage-flow.e2e-spec.ts` | **Modify.** One assertion updated for the new `status()` shape. |
| `backend/src/gmail/gmail-api-client.service.ts` | **Modify.** New `fetchFullBody`/`sendReply` methods. |
| `backend/test/support/fake-gmail-api-client.ts` | **Modify.** New fake methods. |
| `backend/src/calendar/calendar-api-client.service.ts` | **Create.** `criarEvento`. |
| `backend/src/calendar/calendar.module.ts` | **Create.** |
| `backend/test/support/fake-calendar-api-client.ts` | **Create.** |
| `backend/src/email-sync/email-sync.service.ts` | **Modify.** New `getOwned` (tenant-scoped single-row lookup). |
| `backend/src/email-reply/email-draft.service.ts` | **Create.** |
| `backend/src/email-reply/email-commitment-extraction.service.ts` | **Create.** |
| `backend/src/email-reply/dto/enviar-resposta.dto.ts` | **Create.** |
| `backend/src/email-reply/dto/confirmar-compromisso.dto.ts` | **Create.** |
| `backend/src/email-reply/email-reply.controller.ts` | **Create.** |
| `backend/src/email-reply/email-reply.module.ts` | **Create.** |
| `backend/src/app.module.ts` | **Modify.** Register `EmailReplyModule`/`CalendarModule`. |
| `backend/test/email-reply-flow.e2e-spec.ts` | **Create.** |
| `mobile/lib/features/email_triage/email_triage_providers.dart` | **Modify.** 3 OAuth scopes; new repository provider. |
| `mobile/lib/features/email_triage/gmail_connection_repository.dart` | **Modify.** `GmailConnectionStatus` gains the 2 scope flags. |
| `mobile/test/features/email_triage/gmail_connection_repository_test.dart` | **Modify.** New assertions for the 2 flags. |
| `mobile/lib/features/email_triage/rascunhos_email.dart` | **Create.** |
| `mobile/lib/features/email_triage/compromisso_sugerido.dart` | **Create.** |
| `mobile/lib/features/email_triage/email_reply_repository.dart` | **Create.** |
| `mobile/test/features/email_triage/email_reply_repository_test.dart` | **Create.** |
| `mobile/lib/features/email_triage/email_detail_screen.dart` | **Create.** |
| `mobile/lib/features/email_triage/inbox_screen.dart` | **Modify.** `_EmailTile` gains `onTap`. |

---

### Task 1: `GmailConnection` gains scope flags

**Files:**
- Modify: `backend/prisma/schema.prisma`

**Interfaces:**
- Produces: `GmailConnection.temEscopoEnvio: boolean`, `GmailConnection.temEscopoAgenda: boolean`
  (both `@default(false)`) — consumed by Task 2.

- [ ] **Step 1: Edit the `GmailConnection` model**

In `backend/prisma/schema.prisma`, replace the `GmailConnection` model:

```prisma
model GmailConnection {
  id                        String    @id @default(uuid())
  userId                    String    @unique @map("user_id")
  user                      User      @relation(fields: [userId], references: [id])
  refreshTokenCriptografado String    @map("refresh_token_criptografado")
  gmailEmail                String    @map("gmail_email")
  lastHistoryId             String?   @map("last_history_id")
  ultimaSincronizacao       DateTime? @map("ultima_sincronizacao")
  temEscopoEnvio            Boolean   @default(false) @map("tem_escopo_envio")
  temEscopoAgenda           Boolean   @default(false) @map("tem_escopo_agenda")
  criadoEm                  DateTime  @default(now()) @map("criado_em")

  @@map("conexoes_gmail")
}
```

- [ ] **Step 2: Generate the migration**

Run from `backend/`: `npx prisma migrate dev --name add_email_reply_scopes`

Expected: a new folder under `backend/prisma/migrations/` containing an `ALTER TABLE
"conexoes_gmail" ADD COLUMN "tem_escopo_envio" BOOLEAN NOT NULL DEFAULT false;` (and the same for
`tem_escopo_agenda`), applied cleanly against the local dev database, and the Prisma client
regenerated (the command does this automatically).

- [ ] **Step 3: Commit**

```bash
git add backend/prisma/schema.prisma backend/prisma/migrations
git commit -m "feat(gmail): add temEscopoEnvio/temEscopoAgenda to GmailConnection"
```

---

### Task 2: Capture and persist granted OAuth scopes

**Files:**
- Modify: `backend/src/gmail/gmail-oauth.service.ts`
- Modify: `backend/src/gmail/gmail-connections.service.ts`
- Modify: `backend/test/support/fake-gmail-oauth.ts`
- Modify: `backend/test/email-triage-flow.e2e-spec.ts`
- Test: `backend/src/gmail/gmail-connections.service.spec.ts` (already exists — extend it)

**Interfaces:**
- Consumes: `GmailConnection.temEscopoEnvio`/`.temEscopoAgenda` (Task 1).
- Produces: `GmailConnectionsService.getConnectionOrThrow(userId: string):
  Promise<GmailConnection>` (throws `ForbiddenException` if not connected) — consumed by Task 7.
  `GmailConnectionsService.status()`'s return type gains `temEscopoEnvio`/`temEscopoAgenda` —
  consumed by mobile Task 9.

Current content of `backend/src/gmail/gmail-oauth.service.ts` (`exchangeServerAuthCode` method,
lines 10-21):

```typescript
  async exchangeServerAuthCode(serverAuthCode: string): Promise<{ refreshToken: string }> {
    const client = this.buildClient();
    const { tokens } = await client.getToken(serverAuthCode);
    if (!tokens.refresh_token) {
      throw new UnprocessableEntityException(
        'O Google não retornou um refresh token. Isso geralmente acontece quando o acesso já ' +
          'foi concedido antes — revogue o acesso em https://myaccount.google.com/permissions ' +
          'e tente conectar novamente.',
      );
    }
    return { refreshToken: tokens.refresh_token };
  }
```

Current content of `backend/src/gmail/gmail-connections.service.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { TokenCryptoService } from '../crypto/token-crypto.service';
import { GmailOAuthService } from './gmail-oauth.service';

@Injectable()
export class GmailConnectionsService {
  private readonly logger = new Logger(GmailConnectionsService.name);

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
      try {
        await this.oauthService.revoke(refreshToken);
      } catch (error) {
        this.logger.warn(
          `Failed to revoke Gmail refresh token with Google during disconnect (continuing with local cleanup): ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    }
    await this.prisma.emailSummary.deleteMany({ where: { userId: user.id } });
    await this.prisma.gmailConnection.deleteMany({ where: { userId: user.id } });
  }
}
```

- [ ] **Step 1: Extend `GmailOAuthService.exchangeServerAuthCode`**

Replace the method with:

```typescript
  async exchangeServerAuthCode(serverAuthCode: string): Promise<{ refreshToken: string; scope: string }> {
    const client = this.buildClient();
    const { tokens } = await client.getToken(serverAuthCode);
    if (!tokens.refresh_token) {
      throw new UnprocessableEntityException(
        'O Google não retornou um refresh token. Isso geralmente acontece quando o acesso já ' +
          'foi concedido antes — revogue o acesso em https://myaccount.google.com/permissions ' +
          'e tente conectar novamente.',
      );
    }
    return { refreshToken: tokens.refresh_token, scope: tokens.scope ?? '' };
  }
```

- [ ] **Step 2: Update the fake OAuth used by tests**

Replace the full content of `backend/test/support/fake-gmail-oauth.ts`:

```typescript
const FULL_SCOPE =
  'https://www.googleapis.com/auth/gmail.readonly ' +
  'https://www.googleapis.com/auth/gmail.send ' +
  'https://www.googleapis.com/auth/calendar.events';

export function buildFakeGmailOAuth(options: { scope?: string } = {}) {
  return {
    exchangeServerAuthCode: async (code: string) => ({
      refreshToken: `fake-refresh-token-for-${code}`,
      scope: options.scope ?? FULL_SCOPE,
    }),
    authenticatedClientFor: () => ({}),
    getEmailAddress: async () => 'usuario.teste@gmail.com',
    revoke: async () => undefined,
  };
}
```

This is backward-compatible: every existing call site (`buildFakeGmailOAuth()`, no args) now gets
the full scope string by default — the existing `email-triage-flow.e2e-spec.ts` never asserted on
scope before and doesn't need to change for this step.

- [ ] **Step 3: Update the existing spec file — new tests, plus 3 existing tests whose exact-match
  assertions this change breaks**

The full current content of `backend/src/gmail/gmail-connections.service.spec.ts` is:

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

  it('disconnect still deletes local rows when revoking with Google fails (e.g. already-revoked token)', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue({ refreshTokenCriptografado: 'encrypted(rt-123)' });
    oauthService.revoke.mockRejectedValue(new Error('invalid_grant'));
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await expect(service.disconnect('fb1')).resolves.not.toThrow();

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

Two things change once `connect`/`status` include the two new flags: `buildDeps()`'s
`exchangeServerAuthCode` mock must return a `scope` (Step 5's implementation calls `.split(' ')`
on it, which throws on `undefined`), and every existing `toEqual`/exact `toHaveBeenCalledWith`
assertion on the `upsert` call or the `status()` result must include the two new fields — these
are exact-match assertions, not `objectContaining`, so they silently start failing once the real
`update`/`create` payloads and `status()` return value gain new keys they don't expect.

Replace the full file with:

```typescript
import { GmailConnectionsService } from './gmail-connections.service';

const FULL_SCOPE =
  'https://www.googleapis.com/auth/gmail.readonly ' +
  'https://www.googleapis.com/auth/gmail.send ' +
  'https://www.googleapis.com/auth/calendar.events';

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
    exchangeServerAuthCode: jest.fn().mockResolvedValue({ refreshToken: 'rt-123', scope: FULL_SCOPE }),
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
      update: {
        refreshTokenCriptografado: 'encrypted(rt-123)',
        gmailEmail: 'ana@example.com',
        temEscopoEnvio: true,
        temEscopoAgenda: true,
      },
      create: {
        userId: 'u1',
        refreshTokenCriptografado: 'encrypted(rt-123)',
        gmailEmail: 'ana@example.com',
        temEscopoEnvio: true,
        temEscopoAgenda: true,
      },
    });
  });

  it('persists temEscopoEnvio false when only calendar.events is granted', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    oauthService.exchangeServerAuthCode.mockResolvedValue({
      refreshToken: 'rt-123',
      scope:
        'https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.events',
    });
    prisma.gmailConnection.upsert.mockResolvedValue({ id: 'gc1' });
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await service.connect('fb1', 'auth-code-abc');

    expect(prisma.gmailConnection.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        update: expect.objectContaining({ temEscopoEnvio: false, temEscopoAgenda: true }),
      }),
    );
  });

  it('persists both flags false when neither new scope is granted', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    oauthService.exchangeServerAuthCode.mockResolvedValue({
      refreshToken: 'rt-123',
      scope: 'https://www.googleapis.com/auth/gmail.readonly',
    });
    prisma.gmailConnection.upsert.mockResolvedValue({ id: 'gc1' });
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await service.connect('fb1', 'auth-code-abc');

    expect(prisma.gmailConnection.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        update: expect.objectContaining({ temEscopoEnvio: false, temEscopoAgenda: false }),
      }),
    );
  });

  it('reports connection status scoped to the resolved user, including scope flags', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue({
      gmailEmail: 'ana@example.com',
      temEscopoEnvio: true,
      temEscopoAgenda: false,
    });
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    const status = await service.status('fb1');

    expect(prisma.gmailConnection.findUnique).toHaveBeenCalledWith({ where: { userId: 'u1' } });
    expect(status).toEqual({
      connected: true,
      gmailEmail: 'ana@example.com',
      temEscopoEnvio: true,
      temEscopoAgenda: false,
    });
  });

  it('reports not connected, with both scope flags false, when there is no row', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue(null);
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    const status = await service.status('fb1');

    expect(status).toEqual({
      connected: false,
      gmailEmail: null,
      temEscopoEnvio: false,
      temEscopoAgenda: false,
    });
  });

  it('getConnectionOrThrow returns the connection row when one exists', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    const connection = { userId: 'u1', temEscopoEnvio: true, temEscopoAgenda: true };
    prisma.gmailConnection.findUnique.mockResolvedValue(connection);
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    const result = await service.getConnectionOrThrow('u1');

    expect(result).toEqual(connection);
  });

  it('getConnectionOrThrow throws ForbiddenException when there is no connection', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue(null);
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await expect(service.getConnectionOrThrow('u1')).rejects.toThrow('Gmail não conectado.');
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

  it('disconnect still deletes local rows when revoking with Google fails (e.g. already-revoked token)', async () => {
    const { prisma, usersService, tokenCrypto, oauthService } = buildDeps();
    prisma.gmailConnection.findUnique.mockResolvedValue({ refreshTokenCriptografado: 'encrypted(rt-123)' });
    oauthService.revoke.mockRejectedValue(new Error('invalid_grant'));
    const service = new GmailConnectionsService(prisma as any, usersService as any, tokenCrypto as any, oauthService as any);

    await expect(service.disconnect('fb1')).resolves.not.toThrow();

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

- [ ] **Step 4: Run the tests to verify they fail**

Run: `cd backend && npm test -- gmail-connections.service.spec`
Expected: FAIL — `temEscopoEnvio`/`temEscopoAgenda` are `undefined` in the actual `upsert` call
(the service doesn't compute or pass them yet).

- [ ] **Step 5: Implement scope capture and the new `getConnectionOrThrow` method**

Replace the full content of `backend/src/gmail/gmail-connections.service.ts`:

```typescript
import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { TokenCryptoService } from '../crypto/token-crypto.service';
import { GmailOAuthService } from './gmail-oauth.service';

const GMAIL_SEND_SCOPE = 'https://www.googleapis.com/auth/gmail.send';
const CALENDAR_EVENTS_SCOPE = 'https://www.googleapis.com/auth/calendar.events';

@Injectable()
export class GmailConnectionsService {
  private readonly logger = new Logger(GmailConnectionsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    private readonly tokenCrypto: TokenCryptoService,
    private readonly oauthService: GmailOAuthService,
  ) {}

  async connect(firebaseUid: string, serverAuthCode: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const { refreshToken, scope } = await this.oauthService.exchangeServerAuthCode(serverAuthCode);
    const gmailEmail = await this.oauthService.getEmailAddress(refreshToken);
    const refreshTokenCriptografado = this.tokenCrypto.encrypt(refreshToken);
    const scopesConcedidos = scope.split(' ');
    const temEscopoEnvio = scopesConcedidos.includes(GMAIL_SEND_SCOPE);
    const temEscopoAgenda = scopesConcedidos.includes(CALENDAR_EVENTS_SCOPE);

    return this.prisma.gmailConnection.upsert({
      where: { userId: user.id },
      update: { refreshTokenCriptografado, gmailEmail, temEscopoEnvio, temEscopoAgenda },
      create: { userId: user.id, refreshTokenCriptografado, gmailEmail, temEscopoEnvio, temEscopoAgenda },
    });
  }

  async status(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId: user.id } });
    return {
      connected: connection !== null,
      gmailEmail: connection?.gmailEmail ?? null,
      temEscopoEnvio: connection?.temEscopoEnvio ?? false,
      temEscopoAgenda: connection?.temEscopoAgenda ?? false,
    };
  }

  async getDecryptedRefreshToken(userId: string): Promise<string | null> {
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId } });
    if (!connection) return null;
    return this.tokenCrypto.decrypt(connection.refreshTokenCriptografado);
  }

  /** Used by endpoints that require a connection to exist before doing anything else (drafting,
   *  sending, confirming a calendar event) — throws instead of returning null so those call sites
   *  don't each have to repeat the same null-check/403 boilerplate. */
  async getConnectionOrThrow(userId: string) {
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId } });
    if (!connection) {
      throw new ForbiddenException('Gmail não conectado.');
    }
    return connection;
  }

  async disconnect(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.gmailConnection.findUnique({ where: { userId: user.id } });
    if (connection) {
      const refreshToken = this.tokenCrypto.decrypt(connection.refreshTokenCriptografado);
      try {
        await this.oauthService.revoke(refreshToken);
      } catch (error) {
        this.logger.warn(
          `Failed to revoke Gmail refresh token with Google during disconnect (continuing with local cleanup): ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    }
    await this.prisma.emailSummary.deleteMany({ where: { userId: user.id } });
    await this.prisma.gmailConnection.deleteMany({ where: { userId: user.id } });
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd backend && npm test -- gmail-connections.service.spec`
Expected: PASS (all cases, including the 3 new ones).

- [ ] **Step 7: Update the one existing e2e assertion that checks `status()`'s shape**

In `backend/test/email-triage-flow.e2e-spec.ts`, line 70:

```typescript
    expect(status.body).toEqual({ connected: true, gmailEmail: 'usuario.teste@gmail.com' });
```

becomes:

```typescript
    expect(status.body).toEqual({
      connected: true,
      gmailEmail: 'usuario.teste@gmail.com',
      temEscopoEnvio: true,
      temEscopoAgenda: true,
    });
```

(`true`/`true` because Step 2's updated fake now grants the full scope string by default, and this
e2e test never overrides that.) Also update line 127's `{ connected: false, gmailEmail: null }` to
`{ connected: false, gmailEmail: null, temEscopoEnvio: false, temEscopoAgenda: false }`, and line
136's `{ connected: true, gmailEmail: 'usuario.teste@gmail.com' }` the same way as line 70.

- [ ] **Step 8: Run the full e2e suite to confirm no regression**

Run: `cd backend && npm run test:e2e -- email-triage-flow`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add backend/src/gmail/gmail-oauth.service.ts backend/src/gmail/gmail-connections.service.ts backend/src/gmail/gmail-connections.service.spec.ts backend/test/support/fake-gmail-oauth.ts backend/test/email-triage-flow.e2e-spec.ts
git commit -m "feat(gmail): capture and persist granted OAuth scopes on connect"
```

---

### Task 3: `GmailApiClient` — fetch full body, send reply

**Files:**
- Modify: `backend/src/gmail/gmail-api-client.service.ts`
- Modify: `backend/test/support/fake-gmail-api-client.ts`

**Interfaces:**
- Produces: `GmailApiClient.fetchFullBody(refreshToken: string, gmailMessageId: string):
  Promise<string>` and `GmailApiClient.sendReply(refreshToken: string, params: { gmailMessageId:
  string; para: string; assunto: string; texto: string }): Promise<void>` — both consumed by
  Task 7.

Current content of `backend/src/gmail/gmail-api-client.service.ts` is unchanged above (already
read in Task 2's context) except this task only touches the `GmailApiClient` class body — add the
two methods below at the end of the class, right before its closing `}`, and add
`Buffer`-independent imports are unnecessary (`Buffer` is a Node.js global, no import needed).

- [ ] **Step 1: Add the two methods**

```typescript
  /** Full plain-text body for drafting a reply — `fetchInitialUnread`/`fetchIncremental` above
   *  only ever read the short `snippet` via `format: 'metadata'`; generating a coherent draft
   *  needs the real text. */
  async fetchFullBody(refreshToken: string, gmailMessageId: string): Promise<string> {
    const gmail = this.gmailFor(refreshToken);
    const message = await gmail.users.messages.get({ userId: 'me', id: gmailMessageId, format: 'full' });
    return this.extractPlainTextBody(message.data.payload) ?? message.data.snippet ?? '';
  }

  private extractPlainTextBody(payload: gmail_v1.Schema$MessagePart | undefined): string | null {
    if (!payload) return null;
    if (payload.mimeType === 'text/plain' && payload.body?.data) {
      return Buffer.from(payload.body.data, 'base64url').toString('utf8');
    }
    for (const part of payload.parts ?? []) {
      const found = this.extractPlainTextBody(part);
      if (found) return found;
    }
    return null;
  }

  /** Sends a real reply in the original thread. `params.para` is the original `remetente` field
   *  verbatim (e.g. `"Carlos <carlos@example.com>"`) — valid directly as a `To:` header per
   *  RFC 5322, no parsing needed. */
  async sendReply(
    refreshToken: string,
    params: { gmailMessageId: string; para: string; assunto: string; texto: string },
  ): Promise<void> {
    const gmail = this.gmailFor(refreshToken);
    const original = await gmail.users.messages.get({
      userId: 'me',
      id: params.gmailMessageId,
      format: 'metadata',
      metadataHeaders: ['Message-Id', 'References'],
    });
    const headers = original.data.payload?.headers ?? [];
    const messageIdHeader = headers.find((h) => h.name === 'Message-Id')?.value ?? '';
    const referencesHeader = headers.find((h) => h.name === 'References')?.value ?? '';
    const references = [referencesHeader, messageIdHeader].filter(Boolean).join(' ');

    const raw = [
      `To: ${params.para}`,
      `Subject: Re: ${params.assunto}`,
      `In-Reply-To: ${messageIdHeader}`,
      `References: ${references}`,
      'Content-Type: text/plain; charset="UTF-8"',
      '',
      params.texto,
    ].join('\r\n');
    const encoded = Buffer.from(raw).toString('base64url');

    await gmail.users.messages.send({
      userId: 'me',
      requestBody: { raw: encoded, threadId: original.data.threadId ?? undefined },
    });
  }
```

- [ ] **Step 2: Add fakes for the two new methods**

In `backend/test/support/fake-gmail-api-client.ts`, add two new keys to the returned object
(alongside the existing `fetchInitialUnread`/`fetchIncremental`):

```typescript
    fetchFullBody: async () => 'Corpo completo de teste do e-mail original.',
    sendReply: async () => undefined,
```

- [ ] **Step 3: Run `flutter analyze`-equivalent for backend — TypeScript build check**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/src/gmail/gmail-api-client.service.ts backend/test/support/fake-gmail-api-client.ts
git commit -m "feat(gmail): add fetchFullBody and sendReply to GmailApiClient"
```

---

### Task 4: Calendar module — create event

**Files:**
- Create: `backend/src/calendar/calendar-api-client.service.ts`
- Create: `backend/src/calendar/calendar.module.ts`
- Create: `backend/test/support/fake-calendar-api-client.ts`

**Interfaces:**
- Consumes: `GmailOAuthService.authenticatedClientFor(refreshToken: string)` (already exists,
  returns a `google.auth.OAuth2` client usable by any Google API the token's scopes cover).
- Produces: `CalendarApiClient.criarEvento(refreshToken: string, params: { tituloCompromisso:
  string; dataHoraLimite: string; antecedenciaMinutos: number }): Promise<void>` — consumed by
  Task 7.

- [ ] **Step 1: Create `CalendarApiClient`**

```typescript
// backend/src/calendar/calendar-api-client.service.ts
import { Injectable } from '@nestjs/common';
import { google } from 'googleapis';
import { GmailOAuthService } from '../gmail/gmail-oauth.service';

export interface CriarEventoParams {
  tituloCompromisso: string;
  dataHoraLimite: string; // ISO
  antecedenciaMinutos: number;
}

@Injectable()
export class CalendarApiClient {
  constructor(private readonly oauthService: GmailOAuthService) {}

  /** Creates a real event on the user's primary calendar with two reminders — Google Calendar
   *  itself delivers these notifications; this app has no scheduling mechanism of its own. */
  async criarEvento(refreshToken: string, params: CriarEventoParams): Promise<void> {
    const auth = this.oauthService.authenticatedClientFor(refreshToken);
    const calendar = google.calendar({ version: 'v3', auth });
    const inicio = new Date(params.dataHoraLimite);
    const fim = new Date(inicio.getTime() + 30 * 60 * 1000);

    await calendar.events.insert({
      calendarId: 'primary',
      requestBody: {
        summary: params.tituloCompromisso,
        start: { dateTime: inicio.toISOString() },
        end: { dateTime: fim.toISOString() },
        reminders: {
          useDefault: false,
          overrides: [
            { method: 'popup', minutes: params.antecedenciaMinutos },
            { method: 'popup', minutes: 30 },
          ],
        },
      },
    });
  }
}
```

- [ ] **Step 2: Create `CalendarModule`**

```typescript
// backend/src/calendar/calendar.module.ts
import { Module } from '@nestjs/common';
import { GmailModule } from '../gmail/gmail.module';
import { CalendarApiClient } from './calendar-api-client.service';

@Module({
  imports: [GmailModule],
  providers: [CalendarApiClient],
  exports: [CalendarApiClient],
})
export class CalendarModule {}
```

- [ ] **Step 3: Create the fake for e2e use**

```typescript
// backend/test/support/fake-calendar-api-client.ts
export function buildFakeCalendarApiClient() {
  return {
    criarEvento: async () => undefined,
  };
}
```

- [ ] **Step 4: Build check**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/calendar backend/test/support/fake-calendar-api-client.ts
git commit -m "feat(calendar): add CalendarApiClient for creating primary-calendar events"
```

---

### Task 5: `EmailSyncService.getOwned` — tenant-scoped single-email lookup

**Files:**
- Modify: `backend/src/email-sync/email-sync.service.ts`
- Test: `backend/src/email-sync/email-sync.service.spec.ts` (already exists — extend it)

**Interfaces:**
- Produces: `EmailSyncService.getOwned(firebaseUid: string, id: string): Promise<EmailSummary>`
  (Prisma model type; throws `NotFoundException` if not found or not owned by this user) —
  consumed by Task 7.

- [ ] **Step 1: Write the failing tests**

The existing `backend/src/email-sync/email-sync.service.spec.ts` uses a `buildDeps()` +
`buildService(deps)` pair of helper functions (not a NestJS `TestingModule`) — `buildDeps()`'s
`prisma.emailSummary` mock currently only declares `findUnique`, `create`, and `findMany` as
`jest.fn()`s; add `findFirst` to it too, then add a new `describe('getOwned', ...)` block. In
`buildDeps()`, change:

```typescript
    emailSummary: { findUnique: jest.fn().mockResolvedValue(null), create: jest.fn(), findMany: jest.fn() },
```

to:

```typescript
    emailSummary: {
      findUnique: jest.fn().mockResolvedValue(null),
      findFirst: jest.fn(),
      create: jest.fn(),
      findMany: jest.fn(),
    },
```

Then add this new `describe` block at the end of the file, right before the closing `});` of the
outer `describe('EmailSyncService', ...)`:

```typescript
  describe('getOwned', () => {
    it('returns the summary when it belongs to the authenticated user', async () => {
      const deps = buildDeps();
      const summary = { id: 'summary-1', userId: 'u1', gmailMessageId: 'msg-1' };
      deps.prisma.emailSummary.findFirst.mockResolvedValue(summary);
      const service = buildService(deps);

      const result = await service.getOwned('fb1', 'summary-1');

      expect(result).toEqual(summary);
      expect(deps.prisma.emailSummary.findFirst).toHaveBeenCalledWith({
        where: { id: 'summary-1', userId: 'u1' },
      });
    });

    it('throws NotFoundException when the summary does not exist or belongs to another user', async () => {
      const deps = buildDeps();
      deps.prisma.emailSummary.findFirst.mockResolvedValue(null);
      const service = buildService(deps);

      await expect(service.getOwned('fb1', 'someone-elses-summary')).rejects.toThrow(
        'E-mail não encontrado.',
      );
    });
  });
```

(`buildDeps()`'s `usersService.getByFirebaseUidOrThrow` already resolves to `{ id: 'u1', ... }` by
default — see the existing `buildDeps()` body — so both new tests rely on that same default rather
than re-stubbing it.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && npm test -- email-sync.service.spec`
Expected: FAIL — `service.getOwned is not a function`.

- [ ] **Step 3: Implement `getOwned`**

In `backend/src/email-sync/email-sync.service.ts`, add the import:

```typescript
import { Injectable, Logger, NotFoundException } from '@nestjs/common';
```

(replacing the existing `import { Injectable, Logger } from '@nestjs/common';`), and add the
method right after the existing `list` method, before the file's closing `}`:

```typescript
  async getOwned(firebaseUid: string, id: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const summary = await this.prisma.emailSummary.findFirst({ where: { id, userId: user.id } });
    if (!summary) {
      throw new NotFoundException('E-mail não encontrado.');
    }
    return summary;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && npm test -- email-sync.service.spec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/email-sync/email-sync.service.ts backend/src/email-sync/email-sync.service.spec.ts
git commit -m "feat(email-sync): add tenant-scoped getOwned lookup for a single EmailSummary"
```

---

### Task 6: LLM services — draft generation + commitment extraction

**Files:**
- Create: `backend/src/email-reply/email-draft.service.ts`
- Create: `backend/src/email-reply/email-commitment-extraction.service.ts`
- Test: `backend/src/email-reply/email-draft.service.spec.ts`
- Test: `backend/src/email-reply/email-commitment-extraction.service.spec.ts`

**Interfaces:**
- Produces: `EmailDraftService.gerar(params: { remetente: string; assunto: string; corpo: string
  }): Promise<{ direto: string; formal: string; padrao: string }>` (throws on API/parse failure —
  deliberately not caught here, see comment in the code below);
  `EmailCommitmentExtractionService.extrair(texto: string): Promise<{ tituloCompromisso: string;
  dataHoraLimite: string; antecedenciaMinutos: number } | null>` (never throws — any failure
  degrades to `null`) — both consumed by Task 7.
- Both take an injected `Anthropic` client via their constructor, mirroring
  `LlmEmailClassifier`'s constructor shape in `backend/src/email-classification/llm-email-classifier.service.ts`.

- [ ] **Step 1: Write the failing tests**

```typescript
// backend/src/email-reply/email-draft.service.spec.ts
import { EmailDraftService } from './email-draft.service';

describe('EmailDraftService', () => {
  it('returns the three tone variants parsed from the LLM response', async () => {
    const fakeClient = {
      messages: {
        create: jest.fn().mockResolvedValue({
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                direto: 'Envio até amanhã.',
                formal: 'Prezado, informo que enviarei até amanhã.',
                padrao: 'Envio até amanhã, tudo bem?',
              }),
            },
          ],
        }),
      },
    } as any;
    const service = new EmailDraftService(fakeClient);

    const result = await service.gerar({ remetente: 'Carlos', assunto: 'Prazo', corpo: 'Qual o prazo?' });

    expect(result).toEqual({
      direto: 'Envio até amanhã.',
      formal: 'Prezado, informo que enviarei até amanhã.',
      padrao: 'Envio até amanhã, tudo bem?',
    });
  });

  it('propagates a parse failure instead of silently returning empty drafts', async () => {
    const fakeClient = {
      messages: {
        create: jest.fn().mockResolvedValue({ content: [{ type: 'text', text: 'not json' }] }),
      },
    } as any;
    const service = new EmailDraftService(fakeClient);

    await expect(
      service.gerar({ remetente: 'Carlos', assunto: 'Prazo', corpo: 'Qual o prazo?' }),
    ).rejects.toThrow();
  });
});
```

```typescript
// backend/src/email-reply/email-commitment-extraction.service.spec.ts
import { EmailCommitmentExtractionService } from './email-commitment-extraction.service';

describe('EmailCommitmentExtractionService', () => {
  function buildService(responseText: string) {
    const fakeClient = {
      messages: {
        create: jest.fn().mockResolvedValue({ content: [{ type: 'text', text: responseText }] }),
      },
    } as any;
    return new EmailCommitmentExtractionService(fakeClient);
  }

  it('returns the parsed commitment when the LLM identifies one', async () => {
    const service = buildService(
      JSON.stringify({
        tituloCompromisso: 'Enviar relatório',
        dataHoraLimite: '2026-08-15T15:00:00',
        antecedenciaMinutos: 1440,
      }),
    );

    const result = await service.extrair('Envio o relatório até sexta às 15h.');

    expect(result).toEqual({
      tituloCompromisso: 'Enviar relatório',
      dataHoraLimite: '2026-08-15T15:00:00',
      antecedenciaMinutos: 1440,
    });
  });

  it('returns null when the LLM finds no commitment', async () => {
    const service = buildService('null');

    const result = await service.extrair('Ok, obrigado!');

    expect(result).toBeNull();
  });

  it('returns null (never throws) when the LLM response is malformed', async () => {
    const service = buildService('not json and not the word null either');

    const result = await service.extrair('Envio amanhã.');

    expect(result).toBeNull();
  });

  it('normalizes any antecedenciaMinutos other than 60 to 1440', async () => {
    const service = buildService(
      JSON.stringify({
        tituloCompromisso: 'Ligar',
        dataHoraLimite: '2026-08-15T10:00:00',
        antecedenciaMinutos: 999,
      }),
    );

    const result = await service.extrair('Te ligo amanhã de manhã.');

    expect(result?.antecedenciaMinutos).toBe(1440);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && npm test -- email-reply`
Expected: FAIL — `Cannot find module './email-draft.service'` and
`'./email-commitment-extraction.service'`.

- [ ] **Step 3: Implement `EmailDraftService`**

```typescript
// backend/src/email-reply/email-draft.service.ts
import { Injectable } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';

export interface RascunhosGerados {
  direto: string;
  formal: string;
  padrao: string;
}

@Injectable()
export class EmailDraftService {
  constructor(private readonly client: Anthropic) {}

  /** Unlike LlmEmailClassifier (which runs unattended in a background cron job and must never
   *  throw), this runs synchronously while a person is looking at the screen, able to retry — so
   *  a failure here is allowed to propagate; the controller/mobile layer shows a calm retry UI
   *  instead of silently returning empty drafts. */
  async gerar(params: { remetente: string; assunto: string; corpo: string }): Promise<RascunhosGerados> {
    const response = await this.client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 600,
      messages: [
        {
          role: 'user',
          content:
            'Escreva 3 rascunhos de resposta para o e-mail abaixo, em português, um para cada tom: ' +
            '"direto" (curto e objetivo), "formal" (educado e completo), "padrao" (equilibrado). ' +
            'Responda apenas com um JSON no formato {"direto": "...", "formal": "...", "padrao": "..."}, ' +
            'sem texto extra.\n\n' +
            `De: ${params.remetente}\nAssunto: ${params.assunto}\nCorpo: ${params.corpo}`,
        },
      ],
    });
    const block = response.content[0];
    const text = block.type === 'text' ? block.text : '';
    const parsed = JSON.parse(text) as Partial<RascunhosGerados>;
    if (!parsed.direto || !parsed.formal || !parsed.padrao) {
      throw new Error('Resposta da IA não trouxe os 3 rascunhos esperados.');
    }
    return { direto: parsed.direto, formal: parsed.formal, padrao: parsed.padrao };
  }
}
```

- [ ] **Step 4: Implement `EmailCommitmentExtractionService`**

```typescript
// backend/src/email-reply/email-commitment-extraction.service.ts
import { Injectable } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';

export interface CompromissoSugerido {
  tituloCompromisso: string;
  dataHoraLimite: string; // ISO
  antecedenciaMinutos: number;
}

@Injectable()
export class EmailCommitmentExtractionService {
  constructor(private readonly client: Anthropic) {}

  /** Never throws — a failure here (API error or a malformed response) must never undo an
   *  already-successful send, so every failure mode degrades to "no commitment found". */
  async extrair(texto: string): Promise<CompromissoSugerido | null> {
    try {
      const response = await this.client.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 300,
        messages: [
          {
            role: 'user',
            content:
              'Analise o texto abaixo, escrito como resposta a um e-mail. Identifique se há uma ' +
              'promessa explícita de entrega, reunião ou ação futura com data/horário definido. ' +
              'Se houver, responda apenas com um JSON no formato {"tituloCompromisso": "...", ' +
              '"dataHoraLimite": "AAAA-MM-DDTHH:mm:ss" (data/hora completa, assumindo o ano atual ' +
              'se omitido), "antecedenciaMinutos": 60 ou 1440 (60 para tarefas simples, 1440 para ' +
              'tarefas complexas)}. Se não houver nenhuma promessa com data/horário claro, responda ' +
              'apenas com a palavra null, sem mais nada.\n\n' +
              `Texto: ${texto}`,
          },
        ],
      });
      const block = response.content[0];
      const text = (block.type === 'text' ? block.text : '').trim();
      if (text === 'null') return null;
      const parsed = JSON.parse(text) as Partial<CompromissoSugerido>;
      if (!parsed.tituloCompromisso || !parsed.dataHoraLimite || !parsed.antecedenciaMinutos) return null;
      return {
        tituloCompromisso: parsed.tituloCompromisso,
        dataHoraLimite: parsed.dataHoraLimite,
        antecedenciaMinutos: parsed.antecedenciaMinutos === 60 ? 60 : 1440,
      };
    } catch {
      return null;
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && npm test -- email-reply`
Expected: PASS (6 tests total across both files).

- [ ] **Step 6: Commit**

```bash
git add backend/src/email-reply/email-draft.service.ts backend/src/email-reply/email-commitment-extraction.service.ts backend/src/email-reply/email-draft.service.spec.ts backend/src/email-reply/email-commitment-extraction.service.spec.ts
git commit -m "feat(email-reply): add LLM services for draft generation and commitment extraction"
```

---

### Task 7: `EmailReplyController` + module wiring

**Files:**
- Create: `backend/src/email-reply/dto/enviar-resposta.dto.ts`
- Create: `backend/src/email-reply/dto/confirmar-compromisso.dto.ts`
- Create: `backend/src/email-reply/email-reply.controller.ts`
- Create: `backend/src/email-reply/email-reply.module.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Consumes: `EmailSyncService.getOwned` (Task 5), `GmailConnectionsService.getConnectionOrThrow`/
  `.getDecryptedRefreshToken` (Task 2, existing), `GmailApiClient.fetchFullBody`/`.sendReply`
  (Task 3), `CalendarApiClient.criarEvento` (Task 4), `EmailDraftService.gerar`/
  `EmailCommitmentExtractionService.extrair` (Task 6).
- Produces: `POST /resumos-email/:id/rascunhos`, `POST /resumos-email/:id/enviar`,
  `POST /resumos-email/compromissos/confirmar` — consumed by Task 8 (e2e) and mobile Task 10.

- [ ] **Step 1: Create the two DTOs**

```typescript
// backend/src/email-reply/dto/enviar-resposta.dto.ts
import { IsString, MinLength } from 'class-validator';

export class EnviarRespostaDto {
  @IsString()
  @MinLength(1)
  texto: string;
}
```

```typescript
// backend/src/email-reply/dto/confirmar-compromisso.dto.ts
import { IsIn, IsISO8601, IsInt, IsString, MinLength } from 'class-validator';

export class ConfirmarCompromissoDto {
  @IsString()
  @MinLength(1)
  tituloCompromisso: string;

  @IsISO8601()
  dataHoraLimite: string;

  @IsInt()
  @IsIn([60, 1440])
  antecedenciaMinutos: number;
}
```

- [ ] **Step 2: Create the controller**

```typescript
// backend/src/email-reply/email-reply.controller.ts
import { Body, Controller, ForbiddenException, Param, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from '../users/users.service';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';
import { GmailApiClient } from '../gmail/gmail-api-client.service';
import { CalendarApiClient } from '../calendar/calendar-api-client.service';
import { EmailSyncService } from '../email-sync/email-sync.service';
import { EmailDraftService } from './email-draft.service';
import { EmailCommitmentExtractionService } from './email-commitment-extraction.service';
import { EnviarRespostaDto } from './dto/enviar-resposta.dto';
import { ConfirmarCompromissoDto } from './dto/confirmar-compromisso.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('resumos-email')
export class EmailReplyController {
  constructor(
    private readonly usersService: UsersService,
    private readonly emailSyncService: EmailSyncService,
    private readonly connectionsService: GmailConnectionsService,
    private readonly gmailApiClient: GmailApiClient,
    private readonly calendarApiClient: CalendarApiClient,
    private readonly draftService: EmailDraftService,
    private readonly extractionService: EmailCommitmentExtractionService,
  ) {}

  @Post(':id/rascunhos')
  async gerarRascunhos(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    const summary = await this.emailSyncService.getOwned(firebaseUid, id);
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.connectionsService.getConnectionOrThrow(user.id);
    if (!connection.temEscopoEnvio) {
      throw new ForbiddenException('Reconecte o Gmail para responder por aqui.');
    }
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(user.id);
    const corpo = await this.gmailApiClient.fetchFullBody(refreshToken as string, summary.gmailMessageId);
    return this.draftService.gerar({ remetente: summary.remetente, assunto: summary.assunto, corpo });
  }

  @Post(':id/enviar')
  async enviar(
    @CurrentFirebaseUid() firebaseUid: string,
    @Param('id') id: string,
    @Body() dto: EnviarRespostaDto,
  ) {
    const summary = await this.emailSyncService.getOwned(firebaseUid, id);
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.connectionsService.getConnectionOrThrow(user.id);
    if (!connection.temEscopoEnvio) {
      throw new ForbiddenException('Reconecte o Gmail para responder por aqui.');
    }
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(user.id);
    await this.gmailApiClient.sendReply(refreshToken as string, {
      gmailMessageId: summary.gmailMessageId,
      para: summary.remetente,
      assunto: summary.assunto,
      texto: dto.texto,
    });

    const compromissoSugerido = await this.extractionService.extrair(dto.texto);
    return { enviado: true, compromissoSugerido };
  }

  @Post('compromissos/confirmar')
  async confirmarCompromisso(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: ConfirmarCompromissoDto) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.connectionsService.getConnectionOrThrow(user.id);
    if (!connection.temEscopoAgenda) {
      throw new ForbiddenException('Reconecte o Gmail para usar a agenda.');
    }
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(user.id);
    await this.calendarApiClient.criarEvento(refreshToken as string, dto);
    return { agendado: true };
  }
}
```

- [ ] **Step 3: Create the module**

```typescript
// backend/src/email-reply/email-reply.module.ts
import { Module } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { GmailModule } from '../gmail/gmail.module';
import { CalendarModule } from '../calendar/calendar.module';
import { EmailSyncModule } from '../email-sync/email-sync.module';
import { EmailDraftService } from './email-draft.service';
import { EmailCommitmentExtractionService } from './email-commitment-extraction.service';
import { EmailReplyController } from './email-reply.controller';

const EMAIL_REPLY_ANTHROPIC_CLIENT = 'EMAIL_REPLY_ANTHROPIC_CLIENT';

@Module({
  imports: [AuthModule, UsersModule, GmailModule, CalendarModule, EmailSyncModule],
  providers: [
    {
      provide: EMAIL_REPLY_ANTHROPIC_CLIENT,
      useFactory: () => new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY }),
    },
    {
      provide: EmailDraftService,
      useFactory: (client: Anthropic) => new EmailDraftService(client),
      inject: [EMAIL_REPLY_ANTHROPIC_CLIENT],
    },
    {
      provide: EmailCommitmentExtractionService,
      useFactory: (client: Anthropic) => new EmailCommitmentExtractionService(client),
      inject: [EMAIL_REPLY_ANTHROPIC_CLIENT],
    },
  ],
  controllers: [EmailReplyController],
})
export class EmailReplyModule {}
```

(Mirrors `EmailClassificationModule`'s exact provider-factory shape for the Anthropic client — see
`backend/src/email-classification/email-classification.module.ts` — but with its own locally-scoped
token rather than sharing `ANTHROPIC_CLIENT` across module boundaries, matching the same
independent-client-per-module precedent already used by `backend/src/rag/rag.service.ts`.)

- [ ] **Step 4: Register the new modules in `AppModule`**

In `backend/src/app.module.ts`, add imports for `EmailReplyModule` and `CalendarModule` alongside
the existing feature module imports, and add both to the `imports:` array in the `@Module`
decorator (read the current file first to match its existing import-ordering style before editing).

- [ ] **Step 5: Build check**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add backend/src/email-reply backend/src/app.module.ts
git commit -m "feat(email-reply): add EmailReplyController with drafts/send/confirm endpoints"
```

---

### Task 8: Backend e2e — full reply + calendar flow

**Files:**
- Create: `backend/test/email-reply-flow.e2e-spec.ts`

**Interfaces:**
- Consumes: everything from Tasks 1-7.

- [ ] **Step 1: Write the e2e spec**

```typescript
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
```

- [ ] **Step 2: Run the new e2e spec**

Run: `cd backend && npm run test:e2e -- email-reply-flow`
Expected: PASS (3 tests).

- [ ] **Step 3: Run the full backend test suite to confirm no regression**

Run: `cd backend && npm test && npm run test:e2e`
Expected: PASS across all unit and e2e specs.

- [ ] **Step 4: Commit**

```bash
git add backend/test/email-reply-flow.e2e-spec.ts
git commit -m "test(email-reply): add e2e coverage for drafts, send, extraction, and calendar confirm"
```

---

### Task 9: Mobile — OAuth scopes + `GmailConnectionStatus` extension

**Files:**
- Modify: `mobile/lib/features/email_triage/email_triage_providers.dart`
- Modify: `mobile/lib/features/email_triage/gmail_connection_repository.dart`
- Modify: `mobile/test/features/email_triage/gmail_connection_repository_test.dart`

**Interfaces:**
- Produces: `GmailConnectionStatus.temEscopoEnvio: bool`, `.temEscopoAgenda: bool` — consumed by
  Task 11.

- [ ] **Step 1: Add the two new scopes**

In `mobile/lib/features/email_triage/email_triage_providers.dart`, replace:

```dart
const _gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';

const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn(
    scopes: const [_gmailReadonlyScope],
    serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
  );
});
```

with:

```dart
const _gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';
const _gmailSendScope = 'https://www.googleapis.com/auth/gmail.send';
const _calendarEventsScope = 'https://www.googleapis.com/auth/calendar.events';

const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn(
    scopes: const [_gmailReadonlyScope, _gmailSendScope, _calendarEventsScope],
    serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
  );
});
```

- [ ] **Step 2: Write the failing test for the extended `GmailConnectionStatus`**

Add this test to `mobile/test/features/email_triage/gmail_connection_repository_test.dart`,
alongside the existing `'status parses the connection response'` test:

```dart
  test('status parses the two new scope flags, defaulting to false when absent', () async {
    final mockGoogleSignIn = MockGoogleSignIn();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'connected': true, 'gmailEmail': 'ana@example.com', 'temEscopoEnvio': true, 'temEscopoAgenda': false},
      ));
    }));

    final repository = GmailConnectionRepository(dio, mockGoogleSignIn);
    final status = await repository.status();

    expect(status.temEscopoEnvio, true);
    expect(status.temEscopoAgenda, false);
  });
```

- [ ] **Step 3: Run tests to verify the new test fails**

Run: `cd mobile && flutter test test/features/email_triage/gmail_connection_repository_test.dart`
Expected: FAIL — `The getter 'temEscopoEnvio' isn't defined for the type 'GmailConnectionStatus'`.

- [ ] **Step 4: Extend `GmailConnectionStatus`**

Replace the full content of `mobile/lib/features/email_triage/gmail_connection_repository.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GmailConnectionStatus {
  const GmailConnectionStatus({
    required this.connected,
    this.gmailEmail,
    this.temEscopoEnvio = false,
    this.temEscopoAgenda = false,
  });

  final bool connected;
  final String? gmailEmail;
  final bool temEscopoEnvio;
  final bool temEscopoAgenda;

  factory GmailConnectionStatus.fromJson(Map<String, dynamic> json) {
    return GmailConnectionStatus(
      connected: json['connected'] as bool,
      gmailEmail: json['gmailEmail'] as String?,
      temEscopoEnvio: json['temEscopoEnvio'] as bool? ?? false,
      temEscopoAgenda: json['temEscopoAgenda'] as bool? ?? false,
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

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/email_triage/gmail_connection_repository_test.dart`
Expected: PASS (5 tests, including the new one).

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/email_triage/email_triage_providers.dart mobile/lib/features/email_triage/gmail_connection_repository.dart mobile/test/features/email_triage/gmail_connection_repository_test.dart
git commit -m "feat(email-triage): request gmail.send/calendar.events scopes, expose grant status"
```

---

### Task 10: Mobile — reply models + `EmailReplyRepository`

**Files:**
- Create: `mobile/lib/features/email_triage/rascunhos_email.dart`
- Create: `mobile/lib/features/email_triage/compromisso_sugerido.dart`
- Create: `mobile/lib/features/email_triage/email_reply_repository.dart`
- Modify: `mobile/lib/features/email_triage/email_triage_providers.dart`
- Test: `mobile/test/features/email_triage/email_reply_repository_test.dart`

**Interfaces:**
- Produces: `RascunhosEmail(direto, formal, padrao)`, `CompromissoSugerido(tituloCompromisso,
  dataHoraLimite, antecedenciaMinutos)`, `EmailReplyRepository.gerarRascunhos(String emailId):
  Future<RascunhosEmail>`, `.enviar(String emailId, String texto): Future<EnvioResultado>`,
  `.confirmarCompromisso(CompromissoSugerido): Future<void>`, `emailReplyRepositoryProvider` —
  consumed by Task 11.

- [ ] **Step 1: Create the two data models**

```dart
// mobile/lib/features/email_triage/rascunhos_email.dart
class RascunhosEmail {
  const RascunhosEmail({required this.direto, required this.formal, required this.padrao});

  final String direto;
  final String formal;
  final String padrao;

  factory RascunhosEmail.fromJson(Map<String, dynamic> json) {
    return RascunhosEmail(
      direto: json['direto'] as String? ?? '',
      formal: json['formal'] as String? ?? '',
      padrao: json['padrao'] as String? ?? '',
    );
  }
}
```

```dart
// mobile/lib/features/email_triage/compromisso_sugerido.dart
class CompromissoSugerido {
  const CompromissoSugerido({
    required this.tituloCompromisso,
    required this.dataHoraLimite,
    required this.antecedenciaMinutos,
  });

  final String tituloCompromisso;
  final DateTime dataHoraLimite;
  final int antecedenciaMinutos;

  factory CompromissoSugerido.fromJson(Map<String, dynamic> json) {
    return CompromissoSugerido(
      tituloCompromisso: json['tituloCompromisso'] as String,
      dataHoraLimite: DateTime.parse(json['dataHoraLimite'] as String),
      antecedenciaMinutos: json['antecedenciaMinutos'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tituloCompromisso': tituloCompromisso,
      'dataHoraLimite': dataHoraLimite.toIso8601String(),
      'antecedenciaMinutos': antecedenciaMinutos,
    };
  }
}
```

- [ ] **Step 2: Write the failing repository tests**

```dart
// mobile/test/features/email_triage/email_reply_repository_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/compromisso_sugerido.dart';
import 'package:sincro_mobile/features/email_triage/email_reply_repository.dart';

void main() {
  test('gerarRascunhos posts to the right path and parses the response', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'direto': 'a', 'formal': 'b', 'padrao': 'c'},
      ));
    }));

    final repository = EmailReplyRepository(dio);
    final result = await repository.gerarRascunhos('email-1');

    expect(capturedPath, '/resumos-email/email-1/rascunhos');
    expect(result.direto, 'a');
    expect(result.formal, 'b');
    expect(result.padrao, 'c');
  });

  test('enviar posts the texto and parses enviado + compromissoSugerido', () async {
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {
          'enviado': true,
          'compromissoSugerido': {
            'tituloCompromisso': 'Enviar relatório',
            'dataHoraLimite': '2026-09-01T15:00:00',
            'antecedenciaMinutos': 1440,
          },
        },
      ));
    }));

    final repository = EmailReplyRepository(dio);
    final result = await repository.enviar('email-1', 'Envio segunda.');

    expect(capturedData, {'texto': 'Envio segunda.'});
    expect(result.enviado, true);
    expect(result.compromissoSugerido?.tituloCompromisso, 'Enviar relatório');
    expect(result.compromissoSugerido?.antecedenciaMinutos, 1440);
  });

  test('enviar parses a null compromissoSugerido', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'enviado': true, 'compromissoSugerido': null},
      ));
    }));

    final repository = EmailReplyRepository(dio);
    final result = await repository.enviar('email-1', 'Ok.');

    expect(result.compromissoSugerido, isNull);
  });

  test('confirmarCompromisso posts the compromisso as JSON', () async {
    String? capturedPath;
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'agendado': true}));
    }));

    final repository = EmailReplyRepository(dio);
    await repository.confirmarCompromisso(CompromissoSugerido(
      tituloCompromisso: 'Enviar relatório',
      dataHoraLimite: DateTime.parse('2026-09-01T15:00:00'),
      antecedenciaMinutos: 1440,
    ));

    expect(capturedPath, '/resumos-email/compromissos/confirmar');
    expect(capturedData, {
      'tituloCompromisso': 'Enviar relatório',
      'dataHoraLimite': '2026-09-01T15:00:00.000',
      'antecedenciaMinutos': 1440,
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd mobile && flutter test test/features/email_triage/email_reply_repository_test.dart`
Expected: FAIL — `Target of URI doesn't exist:
'package:sincro_mobile/features/email_triage/email_reply_repository.dart'`.

- [ ] **Step 4: Implement `EmailReplyRepository`**

```dart
// mobile/lib/features/email_triage/email_reply_repository.dart
import 'package:dio/dio.dart';
import 'compromisso_sugerido.dart';
import 'rascunhos_email.dart';

class EnvioResultado {
  const EnvioResultado({required this.enviado, this.compromissoSugerido});

  final bool enviado;
  final CompromissoSugerido? compromissoSugerido;

  factory EnvioResultado.fromJson(Map<String, dynamic> json) {
    final compromisso = json['compromissoSugerido'];
    return EnvioResultado(
      enviado: json['enviado'] as bool,
      compromissoSugerido:
          compromisso == null ? null : CompromissoSugerido.fromJson(compromisso as Map<String, dynamic>),
    );
  }
}

class EmailReplyRepository {
  EmailReplyRepository(this._dio);

  final Dio _dio;

  Future<RascunhosEmail> gerarRascunhos(String emailId) async {
    final response = await _dio.post('/resumos-email/$emailId/rascunhos');
    return RascunhosEmail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<EnvioResultado> enviar(String emailId, String texto) async {
    final response = await _dio.post('/resumos-email/$emailId/enviar', data: {'texto': texto});
    return EnvioResultado.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> confirmarCompromisso(CompromissoSugerido compromisso) async {
    await _dio.post('/resumos-email/compromissos/confirmar', data: compromisso.toJson());
  }
}
```

- [ ] **Step 5: Register the provider**

In `mobile/lib/features/email_triage/email_triage_providers.dart`, add the import
`import 'email_reply_repository.dart';` alongside the existing imports, and add at the end of the
file:

```dart
final emailReplyRepositoryProvider = Provider<EmailReplyRepository>((ref) {
  return EmailReplyRepository(ref.watch(apiClientProvider).dio);
});
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/email_triage/`
Expected: PASS (all files in the directory, including the 4 new tests).

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/features/email_triage/rascunhos_email.dart mobile/lib/features/email_triage/compromisso_sugerido.dart mobile/lib/features/email_triage/email_reply_repository.dart mobile/lib/features/email_triage/email_triage_providers.dart mobile/test/features/email_triage/email_reply_repository_test.dart
git commit -m "feat(email-triage): add EmailReplyRepository and its data models"
```

---

### Task 11: Mobile — `EmailDetailScreen` + inbox wiring

**Files:**
- Create: `mobile/lib/features/email_triage/email_detail_screen.dart`
- Modify: `mobile/lib/features/email_triage/inbox_screen.dart`

**Interfaces:**
- Consumes: `emailReplyRepositoryProvider` (Task 10), `gmailConnectionRepositoryProvider`/
  `gmailConnectionStatusProvider` (existing, extended by Task 9), `EmailSummary` (existing).

No automated test for this task — same documented, established convention as every other screen
in this app (Conexão Profissional, Alívio Sensorial, the Biofeedback-alert connector screen from
the previous feature): no `pumpWidget` tests, UI covered by manual verification (Task 12). The
logic this screen depends on (`EmailReplyRepository`, `GmailConnectionStatus`) is already unit
tested in Tasks 9-10.

- [ ] **Step 1: Create `EmailDetailScreen`**

```dart
// mobile/lib/features/email_triage/email_detail_screen.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/dio_error_message.dart';
import 'compromisso_sugerido.dart';
import 'email_summary.dart';
import 'email_triage_providers.dart';
import 'gmail_connection_repository.dart';
import 'rascunhos_email.dart';

enum _EstadoDetalheEmail { carregandoRascunhos, editando, falhaRascunhos, enviando, enviado }

String _formatarDataHora(DateTime dt) {
  final dia = dt.day.toString().padLeft(2, '0');
  final mes = dt.month.toString().padLeft(2, '0');
  final hora = dt.hour.toString().padLeft(2, '0');
  final minuto = dt.minute.toString().padLeft(2, '0');
  return '$dia/$mes às $hora:$minuto';
}

class EmailDetailScreen extends ConsumerStatefulWidget {
  const EmailDetailScreen({super.key, required this.summary});

  final EmailSummary summary;

  @override
  ConsumerState<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends ConsumerState<EmailDetailScreen> {
  _EstadoDetalheEmail _estado = _EstadoDetalheEmail.carregandoRascunhos;
  RascunhosEmail? _rascunhos;
  final _textoController = TextEditingController();
  String? _erro;
  CompromissoSugerido? _compromissoSugerido;
  bool _compromissoConfirmado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregarRascunhos());
  }

  @override
  void dispose() {
    _textoController.dispose();
    super.dispose();
  }

  Future<void> _carregarRascunhos() async {
    setState(() => _estado = _EstadoDetalheEmail.carregandoRascunhos);
    try {
      final rascunhos = await ref.read(emailReplyRepositoryProvider).gerarRascunhos(widget.summary.id);
      if (!mounted) return;
      setState(() {
        _rascunhos = rascunhos;
        _textoController.text = rascunhos.padrao;
        _estado = _EstadoDetalheEmail.editando;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is DioException ? extractServerErrorMessage(e) : 'Não foi possível gerar sugestões agora.';
        _estado = _EstadoDetalheEmail.falhaRascunhos;
      });
    }
  }

  Future<void> _enviar() async {
    setState(() => _estado = _EstadoDetalheEmail.enviando);
    try {
      final resultado =
          await ref.read(emailReplyRepositoryProvider).enviar(widget.summary.id, _textoController.text);
      if (!mounted) return;
      setState(() {
        _compromissoSugerido = resultado.compromissoSugerido;
        _estado = _EstadoDetalheEmail.enviado;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is DioException ? extractServerErrorMessage(e) : 'Não foi possível enviar. Tente novamente.';
        _estado = _EstadoDetalheEmail.editando;
      });
    }
  }

  Future<void> _confirmarCompromisso() async {
    final compromisso = _compromissoSugerido;
    if (compromisso == null) return;
    try {
      await ref.read(emailReplyRepositoryProvider).confirmarCompromisso(compromisso);
      if (!mounted) return;
      setState(() => _compromissoConfirmado = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível agendar agora. Tente novamente.')),
      );
    }
  }

  Future<void> _reconectar() async {
    try {
      await ref.read(gmailConnectionRepositoryProvider).connect();
      ref.invalidate(gmailConnectionStatusProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível reconectar. Tente novamente.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(gmailConnectionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.summary.assunto)),
      body: connectionStatus.when(
        data: (status) => status.temEscopoEnvio ? _corpo(context) : _semEscopoEnvio(context),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _corpo(context),
      ),
    );
  }

  Widget _semEscopoEnvio(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('De: ${widget.summary.remetente}'),
          const SizedBox(height: 8),
          Text(widget.summary.resumoCurto),
          const SizedBox(height: 24),
          const Text('Reconecte o Gmail para responder por aqui.'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _reconectar, child: const Text('Reconectar Gmail')),
        ],
      ),
    );
  }

  Widget _corpo(BuildContext context) {
    switch (_estado) {
      case _EstadoDetalheEmail.carregandoRascunhos:
        return const Center(child: CircularProgressIndicator());
      case _EstadoDetalheEmail.falhaRascunhos:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_erro ?? 'Não foi possível gerar sugestões agora.'),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _carregarRascunhos, child: const Text('Tentar novamente')),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => setState(() => _estado = _EstadoDetalheEmail.editando),
                child: const Text('Escrever do zero'),
              ),
            ],
          ),
        );
      case _EstadoDetalheEmail.editando:
      case _EstadoDetalheEmail.enviando:
        final enviando = _estado == _EstadoDetalheEmail.enviando;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_rascunhos != null) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Direto'),
                      onPressed: () => setState(() => _textoController.text = _rascunhos!.direto),
                    ),
                    ActionChip(
                      label: const Text('Formal'),
                      onPressed: () => setState(() => _textoController.text = _rascunhos!.formal),
                    ),
                    ActionChip(
                      label: const Text('Padrão'),
                      onPressed: () => setState(() => _textoController.text = _rascunhos!.padrao),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _textoController,
                maxLines: 8,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: enviando || _textoController.text.trim().isEmpty ? null : _enviar,
                child: enviando
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Enviar'),
              ),
            ],
          ),
        );
      case _EstadoDetalheEmail.enviado:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Enviado!'),
              if (_compromissoSugerido != null) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_compromissoSugerido!.tituloCompromisso, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(_formatarDataHora(_compromissoSugerido!.dataHoraLimite)),
                        const SizedBox(height: 16),
                        if (_compromissoConfirmado)
                          const Text('Agendado ✓')
                        else
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _confirmarCompromisso,
                                child: const Text('Confirmar no Calendário'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => setState(() => _compromissoSugerido = null),
                                child: const Text('Não agendar'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }
}
```

- [ ] **Step 2: Wire `onTap` on the inbox tile**

In `mobile/lib/features/email_triage/inbox_screen.dart`, add the import
`import 'email_detail_screen.dart';` alongside the existing imports, and change `_EmailTile`'s
`build` method:

```dart
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        summary.precisaAtencao ? Icons.mark_email_unread_outlined : Icons.check_circle_outline,
        color: summary.precisaAtencao ? colors.secondary : colors.onSurfaceVariant,
      ),
      title: Text(summary.assunto),
      subtitle: Text(summary.resumoCurto),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EmailDetailScreen(summary: summary)),
      ),
    );
  }
```

- [ ] **Step 3: Run `flutter analyze` on the whole project**

Run: `cd mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Run the full mobile test suite**

Run: `cd mobile && flutter test`
Expected: PASS, same count as the end of Task 10 (this task adds no new automated tests, per the
established no-`pumpWidget`-tests convention).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/email_triage/email_detail_screen.dart mobile/lib/features/email_triage/inbox_screen.dart
git commit -m "feat(email-triage): add EmailDetailScreen — drafts, send, and calendar confirmation"
```

---

### Task 12: Manual verification (device required)

Not automatable in `flutter test`/`npm test` — same category as every OAuth-consent and
real-external-API-call verification already documented elsewhere in this codebase.

- [ ] **Step 1:** On a real device with an account that already had Gmail connected before this
  feature (readonly-only), open an e-mail marked "precisa de atenção" and confirm the "Reconecte o
  Gmail" message appears instead of drafts.
- [ ] **Step 2:** Tap "Reconectar Gmail", and on the Google consent screen, grant `gmail.send` but
  deny `calendar.events` (if the screen allows granular denial) — confirm the app afterward shows
  drafts/send working, but no compromisso card ever appears after sending, even for a reply that
  clearly promises a deadline.
- [ ] **Step 3:** Reconnect again granting both scopes. Open an e-mail, confirm 3 real AI-generated
  drafts appear, edit one, and send it — confirm the reply actually arrives in the real recipient's
  inbox (use a second test mailbox you control), correctly threaded as a reply.
- [ ] **Step 4:** Send a reply containing an explicit promise ("envio até sexta às 15h") and confirm
  the compromisso card appears with a sensible title/date. Tap "Confirmar no Calendário" and verify
  a real event appears on the connected Google account's calendar, with both reminders configured
  (visible in the event's "Notificações" section).
- [ ] **Step 5:** Send a reply with no commitment ("ok, obrigado!") and confirm no compromisso card
  appears at all.
- [ ] **Step 6:** Force a network failure (airplane mode) right after tapping "Enviar" and confirm
  the composed text stays in the field with a retry option — nothing is lost.

---

## Self-Review Notes

- **Spec coverage:** every numbered item in "Objetivo desta fase" maps to a task (drafts → Tasks
  6/7/11; send → Tasks 3/7/11; compromisso suggestion+confirm → Tasks 4/6/7/11; reconnect →
  Tasks 2/9/11). Every "Arquitetura" subsection has a corresponding task. The spec's "Testes"
  section maps 1:1 onto Tasks 2, 5, 6, 8, 9, 10, and the manual checklist in Task 12.
- **Placeholder scan:** no TBD/TODO; every code step has literal, complete code. Two spots that
  originally said "adapt this to the existing spec file's style" were fixed during self-review by
  actually reading those files and inlining literal code instead (see below).
- **Type consistency:** `CompromissoSugerido`'s three fields (`tituloCompromisso`,
  `dataHoraLimite`, `antecedenciaMinutos`) are named and typed identically across the backend DTO
  (Task 7), the extraction service (Task 6), the e2e test (Task 8), and the mobile model + its
  `toJson()` (Task 10) — confirmed by re-reading each usage side by side.
  `GmailConnectionsService.getConnectionOrThrow` (Task 2) is the exact method name Task 7's
  controller calls. `EmailSyncService.getOwned` (Task 5) is the exact method name Task 7's
  controller calls, and its `NotFoundException` behavior is what Task 8's cross-tenant e2e test
  (404) verifies.
- **Caught during self-review (fixed inline, not left for the implementer to discover):**
  - Task 2's real `gmail-connections.service.spec.ts` mocks `exchangeServerAuthCode` without a
    `scope` field, and 3 existing tests assert exact (`toEqual`) object shapes on `upsert`/
    `status()` — adding the two new fields to production code would have broken all three the
    moment Task 2 landed. Fixed by reading the real file and rewriting Task 2's Step 3 as a full,
    literal replacement of the spec file (new `scope` in the shared fake, updated expectations in
    the 3 pre-existing tests, 2 new tests for partial-scope cases, 2 new tests for
    `getConnectionOrThrow`) instead of "add tests, adapt to existing style."
  - Task 5's real `email-sync.service.spec.ts` uses a `buildDeps()`/`buildService(deps)` pair, and
    `buildDeps()` never declared `prisma.emailSummary.findFirst` as a mock. Fixed by reading the
    real file and giving the exact one-line addition to `buildDeps()` plus tests that match its
    actual per-test `const deps = buildDeps(); ... buildService(deps)` shape.
  - Task 8's second test spins up a second, separately-configured Nest application
    (`narrowApp`) to exercise the narrow-OAuth-scope path — its original draft never called
    `useGlobalPipes`, unlike the main `app`. Fixed by adding the matching `ValidationPipe` call.
