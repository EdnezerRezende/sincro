# Finanças Generativas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Sincro user connect one or more financial institutions via Open Finance (through Pluggy), see a calm "saldo livre" (free balance) and upcoming bills, and receive non-punitive aggregated alerts before something is due.

**Architecture:** Two new NestJS modules mirror the existing Gmail/email-triage split — `PluggyModule` (raw Pluggy API client + connection lifecycle: connect-token, finalize, list, disconnect) and `FinanceSyncModule` (sync orchestration, webhook intake, on-demand sync, saldo-livre calculation, daily alert scheduler). Financial data is mirrored into three new Prisma tables (`conexoes_financeiras`, `contas_financeiras`, `boletos_dda`), refreshed by Pluggy webhooks and by an on-demand sync the mobile app triggers when the Finanças screen opens. Saldo livre is computed on every read, never stored. Mobile adds a `financas` feature (WebView-based Pluggy Connect flow, a summary screen, Home card, and Settings additions), following the same repository + Riverpod-provider pattern as `email_triage`.

**Tech Stack:** NestJS 11 + Prisma 7 (`@prisma/adapter-pg`) + PostgreSQL on the backend; Node 22's built-in `fetch` for the Pluggy HTTP client (no new HTTP dependency); Flutter + Riverpod 3 + `webview_flutter` on mobile.

## Global Constraints

- Tenant isolation: every query against `conexoes_financeiras`/`contas_financeiras`/`boletos_dda` is scoped by `user_id` resolved from the Firebase-verified token via `UsersService.getByFirebaseUidOrThrow` — never from a client-supplied parameter. Same rule as Fase 1 and the e-mail pillar.
- No differentiation by `plano` in this pillar — every authenticated user gets full access, per the approved spec.
- Notifications are always aggregated (never one push per boleto/fatura) and always gated on `dados.toleranciaNotificacao === 'PADRAO'` — `HORARIO_ESPECIFICO` is treated as silent, same known limitation already documented for the e-mail pillar (the anamnese never collected an actual time window).
- Non-punitive tone: no red/alarm styling for overdue items in the mobile UI; overdue items read as "venceu há X dia(s)", not "atrasado"/"urgente".
- The backend never stores bank credentials or card numbers — Pluggy Connect handles authentication with the institution entirely inside the WebView; the backend only ever sees a `pluggyItemId`.
- Alert window is a fixed 3 days before vencimento (not user-configurable in this phase).
- Money fields are `Decimal` in Prisma/Postgres (`@db.Decimal(14, 2)`) — always convert with `.toNumber()` before returning JSON or doing arithmetic, never rely on implicit coercion.
- All new backend files follow the exact patterns in `backend/src/gmail/` and `backend/src/email-sync/` (guard, decorator, module shape, logging style) — this plan calls out the specific file being mirrored at each task.

---

## Prerequisites

Complete these before Task 3 (they gate the first task that talks to a real Pluggy environment):

1. Create a Pluggy account (sandbox is fine for dev) at the Pluggy dashboard and obtain `PLUGGY_CLIENT_ID` / `PLUGGY_CLIENT_SECRET`.
2. This plan's `PluggyApiClient` (Task 2) targets a standard shape for Pluggy's `/auth`, `/connect_token`, `/items/{id}`, `/accounts`, and `/bills` endpoints. Pluggy's API can evolve — before pointing `PluggyApiClient` at a real sandbox, confirm the current request/response shapes against Pluggy's live API reference and adjust field names if they differ. The unit tests in Task 2 mock `fetch` directly and do not depend on this being exactly right; only real sandbox usage does.
3. This plan's webhook verification (Task 5) assumes Pluggy signs webhook deliveries with HMAC-SHA256 over the raw request body, sent in an `x-pluggy-signature` header. Confirm the current header name/algorithm against Pluggy's webhook docs before going live; adjust `FinanceWebhookController.verifySignature` if it differs.
4. Register a webhook URL in the Pluggy dashboard pointing at `<backend-public-url>/financas/webhooks/pluggy`, and generate/copy the signing secret into `PLUGGY_WEBHOOK_SECRET`.
5. Confirm whether Pluggy's boleto/DDA product needs to be explicitly enabled per-connector in the Connect widget configuration (some connectors require an extra consent toggle) — if so, add the relevant widget query parameter in Task 11's WebView URL.
6. Generate a value for `PLUGGY_WEBHOOK_SECRET` locally too (any random string is fine for dev, e.g. `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`), matching the pattern already used for `TOKEN_ENCRYPTION_KEY`.

---

## Task 1: Prisma schema — financial models

**Files:**
- Modify: `backend/prisma/schema.prisma`
- Create: `backend/prisma/migrations/<timestamp>_add_financas_generativas/migration.sql` (generated by Prisma CLI, not hand-written)

**Interfaces:**
- Produces: `User.diaRecebimento: number | null`; models `FinanceConnection` (table `conexoes_financeiras`), `FinanceAccount` (table `contas_financeiras`), `BoletoDda` (table `boletos_dda`), all consumed by every later backend task.

- [ ] **Step 1: Edit `backend/prisma/schema.prisma`**

Add `diaRecebimento` and the three relations to `User`, and the three new models:

```prisma
model User {
  id              String           @id @default(uuid())
  firebaseUid     String           @unique @map("firebase_uid")
  nome            String
  createdAt       DateTime         @default(now()) @map("created_at")
  plano           String           @default("simples")
  fcmToken        String?          @map("fcm_token")
  diaRecebimento  Int?             @map("dia_recebimento")
  sensoryProfile  SensoryProfile?
  trustedContacts TrustedContact[]
  gmailConnection GmailConnection?
  emailSummaries  EmailSummary[]
  financeConnections FinanceConnection[]
  boletosDda      BoletoDda[]

  @@map("usuarios")
}

model FinanceConnection {
  id           String           @id @default(uuid())
  userId       String           @map("user_id")
  user         User             @relation(fields: [userId], references: [id])
  pluggyItemId String           @map("pluggy_item_id")
  instituicao  String
  status       String
  criadoEm     DateTime         @default(now()) @map("criado_em")
  contas       FinanceAccount[]

  @@unique([userId, pluggyItemId])
  @@index([userId])
  @@map("conexoes_financeiras")
}

model FinanceAccount {
  id               String            @id @default(uuid())
  conexaoId        String            @map("conexao_id")
  conexao          FinanceConnection @relation(fields: [conexaoId], references: [id])
  pluggyAccountId  String            @map("pluggy_account_id")
  tipo             String
  nome             String
  saldoOuFatura    Decimal           @map("saldo_ou_fatura") @db.Decimal(14, 2)
  vencimentoFatura DateTime?         @map("vencimento_fatura") @db.Date
  notificadoEm     DateTime?         @map("notificado_em")
  atualizadoEm     DateTime          @default(now()) @updatedAt @map("atualizado_em")

  @@unique([conexaoId, pluggyAccountId])
  @@index([conexaoId])
  @@map("contas_financeiras")
}

model BoletoDda {
  id           String    @id @default(uuid())
  userId       String    @map("user_id")
  user         User      @relation(fields: [userId], references: [id])
  codigoBarras String    @map("codigo_barras")
  valor        Decimal   @db.Decimal(14, 2)
  vencimento   DateTime  @db.Date
  pago         Boolean   @default(false)
  notificadoEm DateTime? @map("notificado_em")
  criadoEm     DateTime  @default(now()) @map("criado_em")

  @@unique([userId, codigoBarras])
  @@index([userId])
  @@map("boletos_dda")
}
```

- [ ] **Step 2: Generate and apply the migration**

Run: `cd backend && npx prisma migrate dev --name add_financas_generativas`
Expected: a new folder under `backend/prisma/migrations/` is created, the migration applies cleanly against the local dev database, and the Prisma client regenerates.

- [ ] **Step 3: Verify migration status**

Run: `cd backend && npx prisma migrate status`
Expected: "Database schema is up to date!"

- [ ] **Step 4: Commit**

```bash
git add backend/prisma/schema.prisma backend/prisma/migrations
git commit -m "feat: add Prisma schema for finance connections, accounts, and DDA boletos"
```

---

## Task 2: Pluggy API client

**Files:**
- Create: `backend/src/pluggy/pluggy-api-client.service.ts`
- Create: `backend/src/pluggy/pluggy-api-client.service.spec.ts`
- Create: `backend/src/pluggy/pluggy.module.ts`
- Modify: `backend/.env.example`

**Interfaces:**
- Produces: `PluggyApiClient` with `createConnectToken(): Promise<string>`, `getItem(itemId: string): Promise<{ id: string; connector: { name: string }; status: string }>`, `listAccounts(itemId: string): Promise<PluggyAccount[]>`, `listBoletos(itemId: string): Promise<PluggyBoleto[]>`, `deleteItem(itemId: string): Promise<void>`, where `PluggyAccount = { id: string; type: 'BANK' | 'CREDIT'; name: string; balance: number; creditData?: { balanceCloseDate: string } }` and `PluggyBoleto = { codigoBarras: string; valor: number; vencimento: string }`. Consumed by `FinanceConnectionsService` (Task 3) and `FinanceSyncService` (Task 4).

- [ ] **Step 1: Write the failing test**

Create `backend/src/pluggy/pluggy-api-client.service.spec.ts`:

```typescript
import { PluggyApiClient } from './pluggy-api-client.service';

function jsonResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response;
}

describe('PluggyApiClient', () => {
  const originalFetch = global.fetch;
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env.PLUGGY_CLIENT_ID = 'client-id';
    process.env.PLUGGY_CLIENT_SECRET = 'client-secret';
  });

  afterEach(() => {
    global.fetch = originalFetch;
    process.env = { ...originalEnv };
  });

  it('authenticates once and reuses the cached apiKey across calls', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(jsonResponse({ apiKey: 'key-1' }))
      .mockResolvedValueOnce(jsonResponse({ results: [] }))
      .mockResolvedValueOnce(jsonResponse({ results: [] }));
    global.fetch = fetchMock as unknown as typeof fetch;

    const client = new PluggyApiClient();
    await client.listAccounts('item-1');
    await client.listAccounts('item-1');

    const authCalls = fetchMock.mock.calls.filter((call) => (call[0] as string).endsWith('/auth'));
    expect(authCalls).toHaveLength(1);
  });

  it('lists accounts mapped from the Pluggy response', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(jsonResponse({ apiKey: 'key-1' }))
      .mockResolvedValueOnce(
        jsonResponse({ results: [{ id: 'acc-1', type: 'BANK', name: 'Conta Corrente', balance: 1500 }] }),
      );
    global.fetch = fetchMock as unknown as typeof fetch;

    const client = new PluggyApiClient();
    const accounts = await client.listAccounts('item-1');

    expect(accounts).toEqual([{ id: 'acc-1', type: 'BANK', name: 'Conta Corrente', balance: 1500 }]);
  });

  it('refreshes the apiKey and retries once when a request returns 403', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(jsonResponse({ apiKey: 'key-1' }))
      .mockResolvedValueOnce(jsonResponse({}, 403))
      .mockResolvedValueOnce(jsonResponse({ apiKey: 'key-2' }))
      .mockResolvedValueOnce(jsonResponse({ results: [] }));
    global.fetch = fetchMock as unknown as typeof fetch;

    const client = new PluggyApiClient();
    await expect(client.listAccounts('item-1')).resolves.toEqual([]);

    const authCalls = fetchMock.mock.calls.filter((call) => (call[0] as string).endsWith('/auth'));
    expect(authCalls).toHaveLength(2);
  });

  it('throws when PLUGGY_CLIENT_ID/PLUGGY_CLIENT_SECRET are not configured', async () => {
    delete process.env.PLUGGY_CLIENT_ID;
    const client = new PluggyApiClient();

    await expect(client.listAccounts('item-1')).rejects.toThrow(
      'PLUGGY_CLIENT_ID/PLUGGY_CLIENT_SECRET não configurados.',
    );
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/pluggy/pluggy-api-client.service.spec.ts`
Expected: FAIL — `Cannot find module './pluggy-api-client.service'`

- [ ] **Step 3: Write minimal implementation**

Create `backend/src/pluggy/pluggy-api-client.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';

const PLUGGY_BASE_URL = process.env.PLUGGY_BASE_URL ?? 'https://api.pluggy.ai';

export interface PluggyAccount {
  id: string;
  type: 'BANK' | 'CREDIT';
  name: string;
  balance: number;
  creditData?: { balanceCloseDate: string };
}

export interface PluggyBoleto {
  codigoBarras: string;
  valor: number;
  vencimento: string;
}

export interface PluggyItem {
  id: string;
  connector: { name: string };
  status: string;
}

@Injectable()
export class PluggyApiClient {
  private apiKey: string | null = null;

  async createConnectToken(): Promise<string> {
    const data = await this.request<{ accessToken: string }>('/connect_token', {
      method: 'POST',
      body: JSON.stringify({}),
    });
    return data.accessToken;
  }

  async getItem(itemId: string): Promise<PluggyItem> {
    return this.request<PluggyItem>(`/items/${itemId}`);
  }

  async listAccounts(itemId: string): Promise<PluggyAccount[]> {
    const data = await this.request<{ results: PluggyAccount[] }>(`/accounts?itemId=${itemId}`);
    return data.results;
  }

  async listBoletos(itemId: string): Promise<PluggyBoleto[]> {
    const data = await this.request<{ results: PluggyBoleto[] }>(`/bills?itemId=${itemId}`);
    return data.results;
  }

  async deleteItem(itemId: string): Promise<void> {
    await this.request(`/items/${itemId}`, { method: 'DELETE' });
  }

  private async authenticate(): Promise<string> {
    if (this.apiKey) return this.apiKey;
    const clientId = process.env.PLUGGY_CLIENT_ID;
    const clientSecret = process.env.PLUGGY_CLIENT_SECRET;
    if (!clientId || !clientSecret) {
      throw new Error('PLUGGY_CLIENT_ID/PLUGGY_CLIENT_SECRET não configurados.');
    }
    const response = await fetch(`${PLUGGY_BASE_URL}/auth`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientId, clientSecret }),
    });
    if (!response.ok) throw new Error(`Falha ao autenticar na Pluggy: ${response.status}`);
    const data = (await response.json()) as { apiKey: string };
    this.apiKey = data.apiKey;
    return this.apiKey;
  }

  // Retries exactly once on 403 (expired apiKey) with a freshly-authenticated key. Any other
  // non-OK status is a real failure and propagates immediately.
  private async request<T>(path: string, init?: RequestInit, isRetry = false): Promise<T> {
    const apiKey = await this.authenticate();
    const response = await fetch(`${PLUGGY_BASE_URL}${path}`, {
      ...init,
      headers: { ...(init?.headers ?? {}), 'X-API-KEY': apiKey, 'Content-Type': 'application/json' },
    });
    if (response.status === 403 && !isRetry) {
      this.apiKey = null;
      return this.request<T>(path, init, true);
    }
    if (!response.ok) throw new Error(`Pluggy request failed: ${path} (${response.status})`);
    return response.json() as Promise<T>;
  }
}
```

Create `backend/src/pluggy/pluggy.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { PluggyApiClient } from './pluggy-api-client.service';

@Module({
  providers: [PluggyApiClient],
  exports: [PluggyApiClient],
})
export class PluggyModule {}
```

Add to `backend/.env.example` (append after `ANTHROPIC_API_KEY=""`):

```
PLUGGY_CLIENT_ID=""
PLUGGY_CLIENT_SECRET=""
PLUGGY_WEBHOOK_SECRET=""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/pluggy/pluggy-api-client.service.spec.ts`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/src/pluggy backend/.env.example
git commit -m "feat: add Pluggy API client with apiKey caching and 403 retry"
```

---

## Task 3: Finance connection lifecycle (connect-token, finalize, list, disconnect)

**Files:**
- Create: `backend/src/pluggy/finance-connections.service.ts`
- Create: `backend/src/pluggy/finance-connections.service.spec.ts`
- Create: `backend/src/pluggy/finance.controller.ts`
- Create: `backend/src/pluggy/dto/finalize-connection.dto.ts`
- Modify: `backend/src/pluggy/pluggy.module.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Consumes: `PluggyApiClient` (Task 2); `UsersService.getByFirebaseUidOrThrow` (existing, `backend/src/users/users.service.ts`); `FirebaseAuthGuard` and `CurrentFirebaseUid` (existing).
- Produces: `FinanceConnectionsService` with `createConnectToken(): Promise<{ connectToken: string }>`, `finalizeConnection(firebaseUid: string, itemId: string): Promise<{ id: string; instituicao: string; status: string }>`, `listConnections(firebaseUid: string): Promise<{ id: string; instituicao: string; status: string }[]>`, `disconnect(firebaseUid: string, connectionId: string): Promise<void>`. Routes: `POST /financas/connect-token`, `POST /financas/conexoes`, `GET /financas/conexoes`, `DELETE /financas/conexoes/:id`, all behind `FirebaseAuthGuard`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/pluggy/finance-connections.service.spec.ts`:

```typescript
import { FinanceConnectionsService } from './finance-connections.service';

function buildDeps() {
  const prisma = {
    financeConnection: {
      upsert: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
    },
    financeAccount: { deleteMany: jest.fn() },
    boletoDda: { deleteMany: jest.fn() },
  };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
  const pluggyApiClient = {
    createConnectToken: jest.fn().mockResolvedValue('connect-token-abc'),
    getItem: jest.fn().mockResolvedValue({ id: 'item-1', connector: { name: 'Banco Teste' }, status: 'UPDATED' }),
    deleteItem: jest.fn().mockResolvedValue(undefined),
  };
  return { prisma, usersService, pluggyApiClient };
}

describe('FinanceConnectionsService', () => {
  it('returns a connect token from Pluggy', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    const result = await service.createConnectToken();

    expect(result).toEqual({ connectToken: 'connect-token-abc' });
  });

  it('finalizes a connection by fetching the item and upserting the row', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.upsert.mockResolvedValue({ id: 'conn-1', instituicao: 'Banco Teste', status: 'UPDATED' });
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    const result = await service.finalizeConnection('fb1', 'item-1');

    expect(pluggyApiClient.getItem).toHaveBeenCalledWith('item-1');
    expect(prisma.financeConnection.upsert).toHaveBeenCalledWith({
      where: { userId_pluggyItemId: { userId: 'u1', pluggyItemId: 'item-1' } },
      update: { status: 'UPDATED', instituicao: 'Banco Teste' },
      create: { userId: 'u1', pluggyItemId: 'item-1', instituicao: 'Banco Teste', status: 'UPDATED' },
    });
    expect(result).toEqual({ id: 'conn-1', instituicao: 'Banco Teste', status: 'UPDATED' });
  });

  it('lists connections scoped to the resolved user', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.findMany.mockResolvedValue([{ id: 'conn-1', instituicao: 'Banco Teste', status: 'UPDATED' }]);
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    const result = await service.listConnections('fb1');

    expect(prisma.financeConnection.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      select: { id: true, instituicao: true, status: true },
    });
    expect(result).toEqual([{ id: 'conn-1', instituicao: 'Banco Teste', status: 'UPDATED' }]);
  });

  it('disconnect deletes the Pluggy item and local rows, keeping boletos when other connections remain', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    prisma.financeConnection.count.mockResolvedValue(1);
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    await service.disconnect('fb1', 'conn-1');

    expect(pluggyApiClient.deleteItem).toHaveBeenCalledWith('item-1');
    expect(prisma.financeAccount.deleteMany).toHaveBeenCalledWith({ where: { conexaoId: 'conn-1' } });
    expect(prisma.financeConnection.delete).toHaveBeenCalledWith({ where: { id: 'conn-1' } });
    expect(prisma.boletoDda.deleteMany).not.toHaveBeenCalled();
  });

  it('disconnect also wipes boletos when it was the last connection', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    prisma.financeConnection.count.mockResolvedValue(0);
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    await service.disconnect('fb1', 'conn-1');

    expect(prisma.boletoDda.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u1' } });
  });

  it('disconnect still cleans up local rows when the Pluggy delete call fails', async () => {
    const { prisma, usersService, pluggyApiClient } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    prisma.financeConnection.count.mockResolvedValue(0);
    pluggyApiClient.deleteItem.mockRejectedValue(new Error('already revoked'));
    const service = new FinanceConnectionsService(prisma as any, usersService as any, pluggyApiClient as any);

    await expect(service.disconnect('fb1', 'conn-1')).resolves.not.toThrow();
    expect(prisma.financeConnection.delete).toHaveBeenCalledWith({ where: { id: 'conn-1' } });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/pluggy/finance-connections.service.spec.ts`
Expected: FAIL — `Cannot find module './finance-connections.service'`

- [ ] **Step 3: Write minimal implementation**

Create `backend/src/pluggy/finance-connections.service.ts`:

```typescript
import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { PluggyApiClient } from './pluggy-api-client.service';

@Injectable()
export class FinanceConnectionsService {
  private readonly logger = new Logger(FinanceConnectionsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    private readonly pluggyApiClient: PluggyApiClient,
  ) {}

  async createConnectToken(): Promise<{ connectToken: string }> {
    const connectToken = await this.pluggyApiClient.createConnectToken();
    return { connectToken };
  }

  async finalizeConnection(firebaseUid: string, itemId: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const item = await this.pluggyApiClient.getItem(itemId);
    return this.prisma.financeConnection.upsert({
      where: { userId_pluggyItemId: { userId: user.id, pluggyItemId: itemId } },
      update: { status: item.status, instituicao: item.connector.name },
      create: { userId: user.id, pluggyItemId: itemId, instituicao: item.connector.name, status: item.status },
      select: { id: true, instituicao: true, status: true },
    });
  }

  async listConnections(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.financeConnection.findMany({
      where: { userId: user.id },
      select: { id: true, instituicao: true, status: true },
    });
  }

  async disconnect(firebaseUid: string, connectionId: string): Promise<void> {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.prisma.financeConnection.findFirst({
      where: { id: connectionId, userId: user.id },
    });
    if (!connection) {
      throw new NotFoundException('Conexão não encontrada.');
    }

    try {
      await this.pluggyApiClient.deleteItem(connection.pluggyItemId);
    } catch (error) {
      // Best-effort, same reasoning as GmailConnectionsService.disconnect: if the item was
      // already removed on Pluggy's side, local cleanup must still proceed.
      this.logger.warn(
        `Failed to delete Pluggy item during disconnect (continuing with local cleanup): ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }

    await this.prisma.financeAccount.deleteMany({ where: { conexaoId: connection.id } });
    await this.prisma.financeConnection.delete({ where: { id: connection.id } });

    const remaining = await this.prisma.financeConnection.count({ where: { userId: user.id } });
    if (remaining === 0) {
      // boletos_dda is keyed by userId, not by connection (DDA boletos aren't tied to one bank),
      // so they only get cleaned up once no connection is left to justify keeping them.
      await this.prisma.boletoDda.deleteMany({ where: { userId: user.id } });
    }
  }
}
```

Create `backend/src/pluggy/dto/finalize-connection.dto.ts`:

```typescript
import { IsString, MinLength } from 'class-validator';

export class FinalizeConnectionDto {
  @IsString()
  @MinLength(1)
  itemId: string;
}
```

Create `backend/src/pluggy/finance.controller.ts`:

```typescript
import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { FinanceConnectionsService } from './finance-connections.service';
import { FinalizeConnectionDto } from './dto/finalize-connection.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('financas')
export class FinanceController {
  constructor(private readonly connectionsService: FinanceConnectionsService) {}

  @Post('connect-token')
  async createConnectToken() {
    return this.connectionsService.createConnectToken();
  }

  @Post('conexoes')
  async finalize(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: FinalizeConnectionDto) {
    return this.connectionsService.finalizeConnection(firebaseUid, dto.itemId);
  }

  @Get('conexoes')
  async list(@CurrentFirebaseUid() firebaseUid: string) {
    return this.connectionsService.listConnections(firebaseUid);
  }

  @Delete('conexoes/:id')
  async disconnect(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    await this.connectionsService.disconnect(firebaseUid, id);
    return { success: true };
  }
}
```

Update `backend/src/pluggy/pluggy.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { PluggyApiClient } from './pluggy-api-client.service';
import { FinanceConnectionsService } from './finance-connections.service';
import { FinanceController } from './finance.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [PluggyApiClient, FinanceConnectionsService],
  controllers: [FinanceController],
  exports: [PluggyApiClient, FinanceConnectionsService],
})
export class PluggyModule {}
```

Update `backend/src/app.module.ts` — add the import:

```typescript
import { PluggyModule } from './pluggy/pluggy.module';
// ...
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
    PluggyModule,
  ],
})
export class AppModule {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/pluggy/finance-connections.service.spec.ts`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/src/pluggy backend/src/app.module.ts
git commit -m "feat: add finance connection lifecycle (connect-token, finalize, list, disconnect)"
```

---

## Task 4: Finance sync service

**Files:**
- Create: `backend/src/finance-sync/finance-sync.service.ts`
- Create: `backend/src/finance-sync/finance-sync.service.spec.ts`
- Create: `backend/src/finance-sync/finance-sync.module.ts`
- Modify: `backend/src/app.module.ts`

**Interfaces:**
- Consumes: `PluggyApiClient.listAccounts`/`listBoletos` (Task 2); Prisma models `FinanceConnection`, `FinanceAccount`, `BoletoDda` (Task 1).
- Produces: `FinanceSyncService` with `syncConnection(connectionId: string): Promise<void>` and `syncAllForUser(firebaseUid: string): Promise<void>`, both consumed by Task 5 (webhook + on-demand endpoint) and Task 3's tests are unaffected. `FinanceSyncModule` exports `FinanceSyncService`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/finance-sync/finance-sync.service.spec.ts`:

```typescript
import { FinanceSyncService } from './finance-sync.service';

function buildDeps() {
  const prisma = {
    financeConnection: { findUnique: jest.fn(), findMany: jest.fn() },
    financeAccount: { upsert: jest.fn() },
    boletoDda: { upsert: jest.fn() },
  };
  const pluggyApiClient = {
    listAccounts: jest.fn().mockResolvedValue([]),
    listBoletos: jest.fn().mockResolvedValue([]),
  };
  const usersService = { getByFirebaseUidOrThrow: jest.fn().mockResolvedValue({ id: 'u1' }) };
  return { prisma, pluggyApiClient, usersService };
}

describe('FinanceSyncService', () => {
  it('does nothing when the connection no longer exists', async () => {
    const { prisma, pluggyApiClient, usersService } = buildDeps();
    prisma.financeConnection.findUnique.mockResolvedValue(null);
    const service = new FinanceSyncService(prisma as any, pluggyApiClient as any, usersService as any);

    await service.syncConnection('missing');

    expect(pluggyApiClient.listAccounts).not.toHaveBeenCalled();
  });

  it('upserts a BANK account as CORRENTE and a CREDIT account as CARTAO_CREDITO', async () => {
    const { prisma, pluggyApiClient, usersService } = buildDeps();
    prisma.financeConnection.findUnique.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    pluggyApiClient.listAccounts.mockResolvedValue([
      { id: 'acc-1', type: 'BANK', name: 'Conta Corrente', balance: 1500 },
      { id: 'acc-2', type: 'CREDIT', name: 'Cartão', balance: 400, creditData: { balanceCloseDate: '2026-08-10' } },
    ]);
    const service = new FinanceSyncService(prisma as any, pluggyApiClient as any, usersService as any);

    await service.syncConnection('conn-1');

    expect(prisma.financeAccount.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { conexaoId_pluggyAccountId: { conexaoId: 'conn-1', pluggyAccountId: 'acc-1' } },
        create: expect.objectContaining({ tipo: 'CORRENTE', saldoOuFatura: 1500, vencimentoFatura: null }),
      }),
    );
    expect(prisma.financeAccount.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { conexaoId_pluggyAccountId: { conexaoId: 'conn-1', pluggyAccountId: 'acc-2' } },
        create: expect.objectContaining({ tipo: 'CARTAO_CREDITO', saldoOuFatura: 400, vencimentoFatura: new Date('2026-08-10') }),
      }),
    );
  });

  it('upserts boletos scoped to the connection user', async () => {
    const { prisma, pluggyApiClient, usersService } = buildDeps();
    prisma.financeConnection.findUnique.mockResolvedValue({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' });
    pluggyApiClient.listBoletos.mockResolvedValue([
      { codigoBarras: '123456', valor: 100, vencimento: '2026-08-05' },
    ]);
    const service = new FinanceSyncService(prisma as any, pluggyApiClient as any, usersService as any);

    await service.syncConnection('conn-1');

    expect(prisma.boletoDda.upsert).toHaveBeenCalledWith({
      where: { userId_codigoBarras: { userId: 'u1', codigoBarras: '123456' } },
      update: { valor: 100, vencimento: new Date('2026-08-05') },
      create: { userId: 'u1', codigoBarras: '123456', valor: 100, vencimento: new Date('2026-08-05') },
    });
  });

  it('syncAllForUser syncs every connection belonging to the user', async () => {
    const { prisma, pluggyApiClient, usersService } = buildDeps();
    prisma.financeConnection.findMany.mockResolvedValue([{ id: 'conn-1' }, { id: 'conn-2' }]);
    prisma.financeConnection.findUnique
      .mockResolvedValueOnce({ id: 'conn-1', userId: 'u1', pluggyItemId: 'item-1' })
      .mockResolvedValueOnce({ id: 'conn-2', userId: 'u1', pluggyItemId: 'item-2' });
    const service = new FinanceSyncService(prisma as any, pluggyApiClient as any, usersService as any);

    await service.syncAllForUser('fb1');

    expect(prisma.financeConnection.findMany).toHaveBeenCalledWith({ where: { userId: 'u1' }, select: { id: true } });
    expect(pluggyApiClient.listAccounts).toHaveBeenCalledWith('item-1');
    expect(pluggyApiClient.listAccounts).toHaveBeenCalledWith('item-2');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/finance-sync/finance-sync.service.spec.ts`
Expected: FAIL — `Cannot find module './finance-sync.service'`

- [ ] **Step 3: Write minimal implementation**

Create `backend/src/finance-sync/finance-sync.service.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { PluggyApiClient } from '../pluggy/pluggy-api-client.service';

@Injectable()
export class FinanceSyncService {
  private readonly logger = new Logger(FinanceSyncService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly pluggyApiClient: PluggyApiClient,
    private readonly usersService: UsersService,
  ) {}

  async syncConnection(connectionId: string): Promise<void> {
    const connection = await this.prisma.financeConnection.findUnique({ where: { id: connectionId } });
    if (!connection) {
      this.logger.warn(`syncConnection called for unknown connection ${connectionId}`);
      return;
    }

    const accounts = await this.pluggyApiClient.listAccounts(connection.pluggyItemId);
    for (const account of accounts) {
      const tipo = account.type === 'CREDIT' ? 'CARTAO_CREDITO' : 'CORRENTE';
      const vencimentoFatura = account.creditData?.balanceCloseDate
        ? new Date(account.creditData.balanceCloseDate)
        : null;
      await this.prisma.financeAccount.upsert({
        where: { conexaoId_pluggyAccountId: { conexaoId: connection.id, pluggyAccountId: account.id } },
        update: { nome: account.name, saldoOuFatura: account.balance, vencimentoFatura },
        create: {
          conexaoId: connection.id,
          pluggyAccountId: account.id,
          tipo,
          nome: account.name,
          saldoOuFatura: account.balance,
          vencimentoFatura,
        },
      });
    }

    const boletos = await this.pluggyApiClient.listBoletos(connection.pluggyItemId);
    for (const boleto of boletos) {
      const vencimento = new Date(boleto.vencimento);
      await this.prisma.boletoDda.upsert({
        where: { userId_codigoBarras: { userId: connection.userId, codigoBarras: boleto.codigoBarras } },
        update: { valor: boleto.valor, vencimento },
        create: { userId: connection.userId, codigoBarras: boleto.codigoBarras, valor: boleto.valor, vencimento },
      });
    }
  }

  async syncAllForUser(firebaseUid: string): Promise<void> {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connections = await this.prisma.financeConnection.findMany({
      where: { userId: user.id },
      select: { id: true },
    });
    for (const { id } of connections) {
      await this.syncConnection(id);
    }
  }
}
```

Create `backend/src/finance-sync/finance-sync.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { UsersModule } from '../users/users.module';
import { PluggyModule } from '../pluggy/pluggy.module';
import { FinanceSyncService } from './finance-sync.service';

@Module({
  imports: [UsersModule, PluggyModule],
  providers: [FinanceSyncService],
  exports: [FinanceSyncService],
})
export class FinanceSyncModule {}
```

Update `backend/src/app.module.ts` to its full new contents:

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
import { PluggyModule } from './pluggy/pluggy.module';
import { FinanceSyncModule } from './finance-sync/finance-sync.module';

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
    PluggyModule,
    FinanceSyncModule,
  ],
})
export class AppModule {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/finance-sync/finance-sync.service.spec.ts`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/src/finance-sync backend/src/app.module.ts
git commit -m "feat: add finance sync service (accounts + DDA boletos upsert from Pluggy)"
```

---

## Task 5: Webhook intake + on-demand sync endpoint

**Files:**
- Create: `backend/src/finance-sync/finance-webhook.controller.ts`
- Create: `backend/src/finance-sync/finance-webhook.controller.spec.ts`
- Create: `backend/src/finance-sync/finance-sync.controller.ts`
- Modify: `backend/src/finance-sync/finance-sync.module.ts`
- Modify: `backend/src/main.ts`

**Interfaces:**
- Consumes: `FinanceSyncService.syncConnection`/`syncAllForUser` (Task 4).
- Produces: `POST /financas/webhooks/pluggy` (no auth guard — HMAC-verified instead), `POST /financas/sync` (behind `FirebaseAuthGuard`, triggers `syncAllForUser` for the calling user). Both consumed by the mobile client (Task 11/12) and exercised by the e2e test (Task 9).

- [ ] **Step 1: Write the failing test**

Create `backend/src/finance-sync/finance-webhook.controller.spec.ts`:

```typescript
import { createHmac } from 'crypto';
import { UnauthorizedException } from '@nestjs/common';
import { FinanceWebhookController } from './finance-webhook.controller';

function buildDeps() {
  const prisma = { financeConnection: { findFirst: jest.fn() } };
  const financeSyncService = { syncConnection: jest.fn().mockResolvedValue(undefined) };
  return { prisma, financeSyncService };
}

function sign(body: string, secret: string): string {
  return createHmac('sha256', secret).update(body).digest('hex');
}

describe('FinanceWebhookController', () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env.PLUGGY_WEBHOOK_SECRET = 'test-secret';
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it('syncs the matching connection when the signature is valid', async () => {
    const { prisma, financeSyncService } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue({ id: 'conn-1' });
    const controller = new FinanceWebhookController(prisma as any, financeSyncService as any);
    const payload = { event: 'item/updated', itemId: 'item-1' };
    const rawBody = Buffer.from(JSON.stringify(payload));
    const signature = sign(rawBody.toString(), 'test-secret');

    const result = await controller.handleWebhook(payload, signature, { rawBody } as any);

    expect(financeSyncService.syncConnection).toHaveBeenCalledWith('conn-1');
    expect(result).toEqual({ received: true });
  });

  it('acknowledges without syncing when the itemId is unknown', async () => {
    const { prisma, financeSyncService } = buildDeps();
    prisma.financeConnection.findFirst.mockResolvedValue(null);
    const controller = new FinanceWebhookController(prisma as any, financeSyncService as any);
    const payload = { event: 'item/updated', itemId: 'unknown-item' };
    const rawBody = Buffer.from(JSON.stringify(payload));
    const signature = sign(rawBody.toString(), 'test-secret');

    const result = await controller.handleWebhook(payload, signature, { rawBody } as any);

    expect(financeSyncService.syncConnection).not.toHaveBeenCalled();
    expect(result).toEqual({ received: true });
  });

  it('rejects a request with an invalid signature', async () => {
    const { prisma, financeSyncService } = buildDeps();
    const controller = new FinanceWebhookController(prisma as any, financeSyncService as any);
    const payload = { event: 'item/updated', itemId: 'item-1' };
    const rawBody = Buffer.from(JSON.stringify(payload));

    await expect(
      controller.handleWebhook(payload, 'not-the-right-signature-not-the-right-signature', { rawBody } as any),
    ).rejects.toThrow(UnauthorizedException);
    expect(financeSyncService.syncConnection).not.toHaveBeenCalled();
  });

  it('rejects a request with no signature header', async () => {
    const { prisma, financeSyncService } = buildDeps();
    const controller = new FinanceWebhookController(prisma as any, financeSyncService as any);
    const payload = { event: 'item/updated', itemId: 'item-1' };
    const rawBody = Buffer.from(JSON.stringify(payload));

    await expect(controller.handleWebhook(payload, undefined, { rawBody } as any)).rejects.toThrow(UnauthorizedException);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/finance-sync/finance-webhook.controller.spec.ts`
Expected: FAIL — `Cannot find module './finance-webhook.controller'`

- [ ] **Step 3: Write minimal implementation**

Create `backend/src/finance-sync/finance-webhook.controller.ts`:

```typescript
import { Body, Controller, Headers, Post, Req, UnauthorizedException } from '@nestjs/common';
import type { RawBodyRequest } from '@nestjs/common';
import type { Request } from 'express';
import { createHmac, timingSafeEqual } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { FinanceSyncService } from './finance-sync.service';

// Plain interface, not a class-validator DTO: the global ValidationPipe (whitelist: true,
// forbidNonWhitelisted: true) would reject any field Pluggy sends beyond what we declare, and
// Pluggy's webhook payload carries more fields than we use. An interface erases to `Object` at
// runtime, which the ValidationPipe skips entirely — see main.ts's `toValidate` behavior.
interface PluggyWebhookPayload {
  event: string;
  itemId: string;
}

@Controller('financas/webhooks')
export class FinanceWebhookController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly financeSyncService: FinanceSyncService,
  ) {}

  @Post('pluggy')
  async handleWebhook(
    @Body() payload: PluggyWebhookPayload,
    @Headers('x-pluggy-signature') signature: string | undefined,
    @Req() req: RawBodyRequest<Request>,
  ) {
    this.verifySignature(req.rawBody, signature);

    const connection = await this.prisma.financeConnection.findFirst({ where: { pluggyItemId: payload.itemId } });
    if (connection) {
      await this.financeSyncService.syncConnection(connection.id);
    }
    return { received: true };
  }

  private verifySignature(rawBody: Buffer | undefined, signature: string | undefined): void {
    const secret = process.env.PLUGGY_WEBHOOK_SECRET;
    if (!secret) throw new Error('PLUGGY_WEBHOOK_SECRET não configurado.');
    if (!signature || !rawBody) {
      throw new UnauthorizedException('Assinatura do webhook ausente.');
    }
    // Signed over the raw request bytes, not JSON.stringify(payload) — re-serializing the
    // already-parsed body can differ byte-for-byte from what Pluggy actually signed (key
    // ordering, whitespace), which would make every real webhook fail verification.
    const expected = createHmac('sha256', secret).update(rawBody).digest('hex');
    const signatureBuffer = Buffer.from(signature, 'hex');
    const expectedBuffer = Buffer.from(expected, 'hex');
    if (signatureBuffer.length !== expectedBuffer.length || !timingSafeEqual(signatureBuffer, expectedBuffer)) {
      throw new UnauthorizedException('Assinatura do webhook inválida.');
    }
  }
}
```

Create `backend/src/finance-sync/finance-sync.controller.ts`:

```typescript
import { Controller, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { FinanceSyncService } from './finance-sync.service';

@UseGuards(FirebaseAuthGuard)
@Controller('financas')
export class FinanceSyncController {
  constructor(private readonly financeSyncService: FinanceSyncService) {}

  @Post('sync')
  async sync(@CurrentFirebaseUid() firebaseUid: string) {
    await this.financeSyncService.syncAllForUser(firebaseUid);
    return { success: true };
  }
}
```

Update `backend/src/finance-sync/finance-sync.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { PluggyModule } from '../pluggy/pluggy.module';
import { FinanceSyncService } from './finance-sync.service';
import { FinanceWebhookController } from './finance-webhook.controller';
import { FinanceSyncController } from './finance-sync.controller';

@Module({
  imports: [AuthModule, UsersModule, PluggyModule],
  providers: [FinanceSyncService],
  controllers: [FinanceWebhookController, FinanceSyncController],
  exports: [FinanceSyncService],
})
export class FinanceSyncModule {}
```

Update `backend/src/main.ts` to preserve the raw request body (needed for HMAC verification):

```typescript
import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { rawBody: true });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/finance-sync/finance-webhook.controller.spec.ts`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/src/finance-sync backend/src/main.ts
git commit -m "feat: add Pluggy webhook intake and on-demand finance sync endpoint"
```

---

## Task 6: Saldo livre calculator + resumo endpoint

**Files:**
- Create: `backend/src/finance-sync/saldo-livre.calculator.ts`
- Create: `backend/src/finance-sync/saldo-livre.calculator.spec.ts`
- Create: `backend/src/finance-sync/finance-resumo.controller.ts`
- Modify: `backend/src/finance-sync/finance-sync.module.ts`

**Interfaces:**
- Produces: `SaldoLivreCalculator.calcular({ contas, boletos, diaRecebimento, hoje }): { saldoLivre: number; inicioCiclo: Date; fimCiclo: Date }`, where `ContaParaCalculo = { tipo: string; saldoOuFatura: number }` and `BoletoParaCalculo = { valor: number; vencimento: Date; pago: boolean }`. Route `GET /financas/resumo` behind `FirebaseAuthGuard`, returning `{ saldoLivre: number; fimCiclo: string; contas: {...}[]; boletos: {...}[] }`, consumed by the mobile summary screen (Task 12).

- [ ] **Step 1: Write the failing test**

Create `backend/src/finance-sync/saldo-livre.calculator.spec.ts`:

```typescript
import { SaldoLivreCalculator } from './saldo-livre.calculator';

describe('SaldoLivreCalculator', () => {
  const calculator = new SaldoLivreCalculator();
  const hoje = new Date(2026, 7, 3); // 3 de agosto de 2026

  it('subtracts open card bills regardless of the cycle window', () => {
    const result = calculator.calcular({
      contas: [
        { tipo: 'CORRENTE', saldoOuFatura: 1000 },
        { tipo: 'CARTAO_CREDITO', saldoOuFatura: 300 },
      ],
      boletos: [],
      diaRecebimento: null,
      hoje,
    });

    expect(result.saldoLivre).toBe(700);
  });

  it('subtracts unpaid boletos due within the cycle, ignoring ones outside it', () => {
    const result = calculator.calcular({
      contas: [{ tipo: 'CORRENTE', saldoOuFatura: 1000 }],
      boletos: [
        { valor: 100, vencimento: new Date(2026, 7, 5), pago: false }, // dentro (dia_recebimento=10)
        { valor: 50, vencimento: new Date(2026, 7, 15), pago: false }, // fora
        { valor: 999, vencimento: new Date(2026, 7, 5), pago: true }, // pago, ignorado
      ],
      diaRecebimento: 10,
      hoje,
    });

    expect(result.saldoLivre).toBe(900);
  });

  it('rolls the cycle to next month when dia_recebimento already passed this month', () => {
    const result = calculator.calcular({
      contas: [],
      boletos: [{ valor: 100, vencimento: new Date(2026, 8, 1), pago: false }], // 1º de setembro
      diaRecebimento: 1, // já passou em agosto (hoje = 3 de agosto)
      hoje,
    });

    expect(result.fimCiclo).toEqual(new Date(2026, 8, 1));
    expect(result.saldoLivre).toBe(-100);
  });

  it('defaults to the last day of the current month when dia_recebimento is not set', () => {
    const result = calculator.calcular({ contas: [], boletos: [], diaRecebimento: null, hoje });

    expect(result.fimCiclo).toEqual(new Date(2026, 7, 31));
  });

  it('clamps dia_recebimento to the last day of shorter months', () => {
    const fevereiro = new Date(2026, 1, 1); // 1º de fevereiro de 2026 (28 dias)
    const result = calculator.calcular({ contas: [], boletos: [], diaRecebimento: 31, hoje: fevereiro });

    expect(result.fimCiclo).toEqual(new Date(2026, 1, 28));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/finance-sync/saldo-livre.calculator.spec.ts`
Expected: FAIL — `Cannot find module './saldo-livre.calculator'`

- [ ] **Step 3: Write minimal implementation**

Create `backend/src/finance-sync/saldo-livre.calculator.ts`:

```typescript
import { Injectable } from '@nestjs/common';

export interface ContaParaCalculo {
  tipo: string;
  saldoOuFatura: number;
}

export interface BoletoParaCalculo {
  valor: number;
  vencimento: Date;
  pago: boolean;
}

export interface SaldoLivreResult {
  saldoLivre: number;
  inicioCiclo: Date;
  fimCiclo: Date;
}

@Injectable()
export class SaldoLivreCalculator {
  calcular(params: {
    contas: ContaParaCalculo[];
    boletos: BoletoParaCalculo[];
    diaRecebimento: number | null;
    hoje: Date;
  }): SaldoLivreResult {
    const { contas, boletos, diaRecebimento, hoje } = params;
    const inicioCiclo = this.startOfDay(hoje);
    const fimCiclo = this.calcularFimCiclo(diaRecebimento, hoje);

    const saldoContas = this.somar(contas.filter((c) => c.tipo !== 'CARTAO_CREDITO'));
    const faturasAbertas = this.somar(contas.filter((c) => c.tipo === 'CARTAO_CREDITO'));
    const boletosNoCiclo = boletos
      .filter(
        (b) =>
          !b.pago &&
          b.vencimento.getTime() >= inicioCiclo.getTime() &&
          b.vencimento.getTime() <= fimCiclo.getTime(),
      )
      .reduce((sum, b) => sum + b.valor, 0);

    return { saldoLivre: saldoContas - faturasAbertas - boletosNoCiclo, inicioCiclo, fimCiclo };
  }

  private somar(contas: ContaParaCalculo[]): number {
    return contas.reduce((sum, c) => sum + c.saldoOuFatura, 0);
  }

  private calcularFimCiclo(diaRecebimento: number | null, hoje: Date): Date {
    if (diaRecebimento === null) {
      return new Date(hoje.getFullYear(), hoje.getMonth() + 1, 0);
    }
    const esteMs = this.diaClampeado(hoje.getFullYear(), hoje.getMonth(), diaRecebimento);
    if (esteMs.getTime() >= this.startOfDay(hoje).getTime()) {
      return esteMs;
    }
    return this.diaClampeado(hoje.getFullYear(), hoje.getMonth() + 1, diaRecebimento);
  }

  private diaClampeado(year: number, month: number, dia: number): Date {
    const ultimoDiaDoMes = new Date(year, month + 1, 0).getDate();
    return new Date(year, month, Math.min(dia, ultimoDiaDoMes));
  }

  private startOfDay(date: Date): Date {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }
}
```

Create `backend/src/finance-sync/finance-resumo.controller.ts`:

```typescript
import { Controller, Get, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';
import { SaldoLivreCalculator } from './saldo-livre.calculator';

@UseGuards(FirebaseAuthGuard)
@Controller('financas')
export class FinanceResumoController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
    private readonly calculator: SaldoLivreCalculator,
  ) {}

  @Get('resumo')
  async getResumo(@CurrentFirebaseUid() firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connections = await this.prisma.financeConnection.findMany({
      where: { userId: user.id },
      include: { contas: true },
    });
    const contas = connections.flatMap((c) => c.contas);
    const boletos = await this.prisma.boletoDda.findMany({ where: { userId: user.id, pago: false } });

    const resultado = this.calculator.calcular({
      contas: contas.map((c) => ({ tipo: c.tipo, saldoOuFatura: c.saldoOuFatura.toNumber() })),
      boletos: boletos.map((b) => ({ valor: b.valor.toNumber(), vencimento: b.vencimento, pago: b.pago })),
      diaRecebimento: user.diaRecebimento,
      hoje: new Date(),
    });

    return {
      saldoLivre: resultado.saldoLivre,
      fimCiclo: resultado.fimCiclo,
      contas: contas.map((c) => ({
        id: c.id,
        tipo: c.tipo,
        nome: c.nome,
        saldoOuFatura: c.saldoOuFatura.toNumber(),
        vencimentoFatura: c.vencimentoFatura,
      })),
      boletos: boletos.map((b) => ({ id: b.id, valor: b.valor.toNumber(), vencimento: b.vencimento })),
    };
  }
}
```

Update `backend/src/finance-sync/finance-sync.module.ts` to its full new contents:

```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { PluggyModule } from '../pluggy/pluggy.module';
import { FinanceSyncService } from './finance-sync.service';
import { FinanceWebhookController } from './finance-webhook.controller';
import { FinanceSyncController } from './finance-sync.controller';
import { SaldoLivreCalculator } from './saldo-livre.calculator';
import { FinanceResumoController } from './finance-resumo.controller';

@Module({
  imports: [AuthModule, UsersModule, PluggyModule],
  providers: [FinanceSyncService, SaldoLivreCalculator],
  controllers: [FinanceWebhookController, FinanceSyncController, FinanceResumoController],
  exports: [FinanceSyncService],
})
export class FinanceSyncModule {}
```

(`PrismaService` needs no explicit import here — `PrismaModule` is `@Global()`, so it's already available for injection.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/finance-sync/saldo-livre.calculator.spec.ts`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/src/finance-sync
git commit -m "feat: add saldo livre calculator and GET /financas/resumo"
```

---

## Task 7: Dia de recebimento endpoint

**Files:**
- Create: `backend/src/users/dto/update-dia-recebimento.dto.ts`
- Modify: `backend/src/users/users.service.ts`
- Modify: `backend/src/users/users.service.spec.ts`
- Modify: `backend/src/users/users.controller.ts`

**Interfaces:**
- Produces: `UsersService.updateDiaRecebimento(firebaseUid: string, diaRecebimento: number | null): Promise<void>`. Route `PATCH /users/me/dia-recebimento` behind `FirebaseAuthGuard`, consumed by the mobile Settings screen (Task 13).

- [ ] **Step 1: Write the failing test**

Add to `backend/src/users/users.service.spec.ts` (open the existing file and add this `describe` block; if the file does not already export a `buildDeps`-style helper, follow whatever pattern the existing tests in that file use for constructing `UsersService`):

```typescript
describe('updateDiaRecebimento', () => {
  it('updates the resolved user with the given day', async () => {
    const prisma = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'u1' }), update: jest.fn() } };
    const service = new UsersService(prisma as any);

    await service.updateDiaRecebimento('fb1', 15);

    expect(prisma.user.update).toHaveBeenCalledWith({ where: { id: 'u1' }, data: { diaRecebimento: 15 } });
  });

  it('allows clearing the day by passing null', async () => {
    const prisma = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'u1' }), update: jest.fn() } };
    const service = new UsersService(prisma as any);

    await service.updateDiaRecebimento('fb1', null);

    expect(prisma.user.update).toHaveBeenCalledWith({ where: { id: 'u1' }, data: { diaRecebimento: null } });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/users/users.service.spec.ts`
Expected: FAIL — `service.updateDiaRecebimento is not a function`

- [ ] **Step 3: Write minimal implementation**

Create `backend/src/users/dto/update-dia-recebimento.dto.ts`:

```typescript
import { IsInt, IsOptional, Max, Min } from 'class-validator';

export class UpdateDiaRecebimentoDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(31)
  diaRecebimento: number | null;
}
```

Add to `backend/src/users/users.service.ts` (inside the `UsersService` class):

```typescript
  async updateDiaRecebimento(firebaseUid: string, diaRecebimento: number | null): Promise<void> {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);
    await this.prisma.user.update({ where: { id: user.id }, data: { diaRecebimento } });
  }
```

Add to `backend/src/users/users.controller.ts`:

```typescript
import { UpdateDiaRecebimentoDto } from './dto/update-dia-recebimento.dto';
// ...
  @Patch('me/dia-recebimento')
  async updateDiaRecebimento(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: UpdateDiaRecebimentoDto) {
    await this.usersService.updateDiaRecebimento(firebaseUid, dto.diaRecebimento);
    return { success: true };
  }
```

(Add `Patch` to the existing `@nestjs/common` import in `users.controller.ts`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/users/users.service.spec.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/users
git commit -m "feat: add PATCH /users/me/dia-recebimento"
```

---

## Task 8: Daily bill alert scheduler

**Files:**
- Create: `backend/src/finance-sync/finance-alert.scheduler.ts`
- Create: `backend/src/finance-sync/finance-alert.scheduler.spec.ts`
- Modify: `backend/src/notifications/notification.service.ts`
- Modify: `backend/src/notifications/notification.service.spec.ts`
- Modify: `backend/src/finance-sync/finance-sync.module.ts`

**Interfaces:**
- Consumes: `NotificationService` (existing, `backend/src/notifications/notification.service.ts`), extended with `notifyContasVencendo`.
- Produces: `FinanceAlertScheduler.checkContasVencendo(): Promise<void>`, run daily via `@Cron('0 8 * * *')`.

- [ ] **Step 1: Write the failing test**

Create `backend/src/finance-sync/finance-alert.scheduler.spec.ts`:

```typescript
import { FinanceAlertScheduler } from './finance-alert.scheduler';

function buildDeps() {
  const prisma = {
    boletoDda: { findMany: jest.fn().mockResolvedValue([]), updateMany: jest.fn() },
    financeAccount: { findMany: jest.fn().mockResolvedValue([]), updateMany: jest.fn() },
  };
  const notificationService = { notifyContasVencendo: jest.fn().mockResolvedValue(undefined) };
  return { prisma, notificationService };
}

describe('FinanceAlertScheduler', () => {
  it('sends one aggregated notification per user combining boletos and faturas', async () => {
    const { prisma, notificationService } = buildDeps();
    prisma.boletoDda.findMany.mockResolvedValue([{ id: 'boleto-1', userId: 'u1' }]);
    prisma.financeAccount.findMany.mockResolvedValue([
      { id: 'fatura-1', conexao: { userId: 'u1' } },
      { id: 'fatura-2', conexao: { userId: 'u2' } },
    ]);
    const scheduler = new FinanceAlertScheduler(prisma as any, notificationService as any);

    await scheduler.checkContasVencendo();

    expect(notificationService.notifyContasVencendo).toHaveBeenCalledWith('u1', 2);
    expect(notificationService.notifyContasVencendo).toHaveBeenCalledWith('u2', 1);
    expect(prisma.boletoDda.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['boleto-1'] } },
      data: { notificadoEm: expect.any(Date) },
    });
    expect(prisma.financeAccount.updateMany).toHaveBeenCalledWith({
      where: { id: { in: ['fatura-1'] } },
      data: { notificadoEm: expect.any(Date) },
    });
  });

  it('only queries items with notificadoEm still null and vencimento within 3 days', async () => {
    const { prisma, notificationService } = buildDeps();
    const scheduler = new FinanceAlertScheduler(prisma as any, notificationService as any);

    await scheduler.checkContasVencendo();

    expect(prisma.boletoDda.findMany).toHaveBeenCalledWith({
      where: { pago: false, notificadoEm: null, vencimento: { lte: expect.any(Date) } },
    });
    expect(prisma.financeAccount.findMany).toHaveBeenCalledWith({
      where: { tipo: 'CARTAO_CREDITO', notificadoEm: null, vencimentoFatura: { lte: expect.any(Date) } },
      include: { conexao: true },
    });
  });

  it('does not let a failed notification for one user block the others', async () => {
    const { prisma, notificationService } = buildDeps();
    prisma.boletoDda.findMany.mockResolvedValue([
      { id: 'boleto-1', userId: 'u1' },
      { id: 'boleto-2', userId: 'u2' },
    ]);
    notificationService.notifyContasVencendo.mockRejectedValueOnce(new Error('fcm down'));
    const scheduler = new FinanceAlertScheduler(prisma as any, notificationService as any);

    await expect(scheduler.checkContasVencendo()).resolves.not.toThrow();
    expect(notificationService.notifyContasVencendo).toHaveBeenCalledTimes(2);
  });
});
```

Append this `describe` block to the existing `backend/src/notifications/notification.service.spec.ts` (same file already covering `notifyNewEmailsNeedAttention`, using the same `buildDeps` helper already defined at the top of that file):

```typescript
describe('notifyContasVencendo', () => {
  it('sends an aggregated notification when toleranciaNotificacao is PADRAO', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'PADRAO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyContasVencendo('u1', 2);

    expect(send).toHaveBeenCalledWith({
      token: 'token-abc',
      notification: { title: 'Sincro', body: '2 contas estão vencendo nos próximos dias' },
      data: { tipo: 'finance_alert' },
    });
  });

  it('uses singular phrasing for exactly one conta', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'PADRAO' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyContasVencendo('u1', 1);

    expect(send).toHaveBeenCalledWith(
      expect.objectContaining({ notification: expect.objectContaining({ body: '1 conta está vencendo nos próximos dias' }) }),
    );
  });

  it('does not send when toleranciaNotificacao is SILENCIOSAS', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'token-abc' });
    sensoryProfileService.get.mockResolvedValue({ dados: { toleranciaNotificacao: 'SILENCIOSAS' } });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyContasVencendo('u1', 2);

    expect(send).not.toHaveBeenCalled();
  });

  it('does not send when the user has no fcmToken registered', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: null });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);

    await service.notifyContasVencendo('u1', 2);

    expect(send).not.toHaveBeenCalled();
    expect(sensoryProfileService.get).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest src/finance-sync/finance-alert.scheduler.spec.ts src/notifications/notification.service.spec.ts`
Expected: FAIL — `Cannot find module './finance-alert.scheduler'`, and `service.notifyContasVencendo is not a function`

- [ ] **Step 3: Write minimal implementation**

Add to `backend/src/notifications/notification.service.ts` (inside the `NotificationService` class, after `notifyNewEmailsNeedAttention`):

```typescript
  async notifyContasVencendo(userId: string, count: number): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user?.fcmToken) return;

    const sensoryProfile = await this.sensoryProfileService.get(user.firebaseUid);
    const tolerancia = (sensoryProfile?.dados as { toleranciaNotificacao?: string } | undefined)?.toleranciaNotificacao;
    if (tolerancia !== 'PADRAO') return;

    await this.firebaseAdmin.messaging().send({
      token: user.fcmToken,
      notification: {
        title: 'Sincro',
        body: count === 1 ? '1 conta está vencendo nos próximos dias' : `${count} contas estão vencendo nos próximos dias`,
      },
      data: { tipo: 'finance_alert' },
    });
  }
```

Create `backend/src/finance-sync/finance-alert.scheduler.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationService } from '../notifications/notification.service';

const ALERT_WINDOW_DAYS = 3;

@Injectable()
export class FinanceAlertScheduler {
  private readonly logger = new Logger(FinanceAlertScheduler.name);
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationService: NotificationService,
  ) {}

  @Cron('0 8 * * *')
  async checkContasVencendo(): Promise<void> {
    if (this.running) {
      this.logger.warn('checkContasVencendo is already running; skipping this cron firing to avoid overlap');
      return;
    }
    this.running = true;
    try {
      const hoje = new Date();
      const limite = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate() + ALERT_WINDOW_DAYS);

      const boletos = await this.prisma.boletoDda.findMany({
        where: { pago: false, notificadoEm: null, vencimento: { lte: limite } },
      });
      const faturas = await this.prisma.financeAccount.findMany({
        where: { tipo: 'CARTAO_CREDITO', notificadoEm: null, vencimentoFatura: { lte: limite } },
        include: { conexao: true },
      });

      const porUsuario = new Map<string, { boletoIds: string[]; faturaIds: string[] }>();
      for (const boleto of boletos) {
        const entry = porUsuario.get(boleto.userId) ?? { boletoIds: [], faturaIds: [] };
        entry.boletoIds.push(boleto.id);
        porUsuario.set(boleto.userId, entry);
      }
      for (const fatura of faturas) {
        const userId = fatura.conexao.userId;
        const entry = porUsuario.get(userId) ?? { boletoIds: [], faturaIds: [] };
        entry.faturaIds.push(fatura.id);
        porUsuario.set(userId, entry);
      }

      for (const [userId, { boletoIds, faturaIds }] of porUsuario) {
        try {
          await this.notificationService.notifyContasVencendo(userId, boletoIds.length + faturaIds.length);
          if (boletoIds.length > 0) {
            await this.prisma.boletoDda.updateMany({ where: { id: { in: boletoIds } }, data: { notificadoEm: new Date() } });
          }
          if (faturaIds.length > 0) {
            await this.prisma.financeAccount.updateMany({ where: { id: { in: faturaIds } }, data: { notificadoEm: new Date() } });
          }
        } catch (error) {
          this.logger.error(`Failed to notify user ${userId} about upcoming contas`, error as Error);
        }
      }
    } finally {
      this.running = false;
    }
  }
}
```

Update `backend/src/finance-sync/finance-sync.module.ts` to its full new contents:

```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { PluggyModule } from '../pluggy/pluggy.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { FinanceSyncService } from './finance-sync.service';
import { FinanceWebhookController } from './finance-webhook.controller';
import { FinanceSyncController } from './finance-sync.controller';
import { SaldoLivreCalculator } from './saldo-livre.calculator';
import { FinanceResumoController } from './finance-resumo.controller';
import { FinanceAlertScheduler } from './finance-alert.scheduler';

@Module({
  imports: [AuthModule, UsersModule, PluggyModule, NotificationsModule],
  providers: [FinanceSyncService, SaldoLivreCalculator, FinanceAlertScheduler],
  controllers: [FinanceWebhookController, FinanceSyncController, FinanceResumoController],
  exports: [FinanceSyncService],
})
export class FinanceSyncModule {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest src/finance-sync/finance-alert.scheduler.spec.ts src/notifications/notification.service.spec.ts`
Expected: PASS (3 tests in `finance-alert.scheduler.spec.ts`, 9 tests in `notification.service.spec.ts` — 5 pre-existing + 4 new)

- [ ] **Step 5: Commit**

```bash
git add backend/src/finance-sync backend/src/notifications
git commit -m "feat: add daily non-punitive bill alert scheduler"
```

---

## Task 9: Backend e2e test

**Files:**
- Create: `backend/test/finance-flow.e2e-spec.ts`
- Create: `backend/test/support/fake-pluggy-api-client.ts`

**Interfaces:**
- Consumes: every backend piece from Tasks 1–8, exercised end-to-end through `supertest`.

- [ ] **Step 1: Write the failing test**

Create `backend/test/support/fake-pluggy-api-client.ts`:

```typescript
import { PluggyApiClient, PluggyAccount, PluggyBoleto, PluggyItem } from '../../src/pluggy/pluggy-api-client.service';

// Fixture dates are relative to `Date.now()` (tomorrow, +2 days) so they reliably land inside a
// "no dia_recebimento set" cycle (today through the end of the current month) in the finance-flow
// e2e test. This has one known, low-probability flaky edge: if the suite runs on the last day of
// a month, "+1/+2 days" rolls into next month and falls outside that cycle. Not worth freezing the
// clock over; if it ever flakes, the fix is to set the test user's dia_recebimento explicitly via
// PATCH /users/me/dia-recebimento (Task 7) instead of relying on the default end-of-month cycle.
export function buildFakePluggyApiClient(): Partial<PluggyApiClient> {
  const accountsByItem: Record<string, PluggyAccount[]> = {
    'item-tenant-1': [
      { id: 'acc-corrente-1', type: 'BANK', name: 'Conta Corrente', balance: 2000 },
      {
        id: 'acc-cartao-1',
        type: 'CREDIT',
        name: 'Cartão Principal',
        balance: 500,
        creditData: { balanceCloseDate: new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10) },
      },
    ],
    'item-tenant-2': [{ id: 'acc-corrente-2', type: 'BANK', name: 'Conta Corrente', balance: 800 }],
  };
  const boletosByItem: Record<string, PluggyBoleto[]> = {
    'item-tenant-1': [
      {
        codigoBarras: '111.222.333',
        valor: 100,
        vencimento: new Date(Date.now() + 1 * 86400000).toISOString().slice(0, 10),
      },
    ],
    'item-tenant-2': [],
  };

  return {
    createConnectToken: async () => 'fake-connect-token',
    getItem: async (itemId: string): Promise<PluggyItem> => ({
      id: itemId,
      connector: { name: 'Banco Fake' },
      status: 'UPDATED',
    }),
    listAccounts: async (itemId: string) => accountsByItem[itemId] ?? [],
    listBoletos: async (itemId: string) => boletosByItem[itemId] ?? [],
    deleteItem: async () => undefined,
  };
}
```

Create `backend/test/finance-flow.e2e-spec.ts`:

```typescript
import 'dotenv/config';
import { createHmac } from 'crypto';
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { FIREBASE_ADMIN } from '../src/auth/firebase-admin.provider';
import { PluggyApiClient } from '../src/pluggy/pluggy-api-client.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildFakeFirebaseAdmin } from './support/fake-firebase-admin';
import { buildFakePluggyApiClient } from './support/fake-pluggy-api-client';

describe('Finance flow (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  const firebaseUid1 = 'finance-user-1';
  const firebaseUid2 = 'finance-user-2';
  const authHeader = { Authorization: `Bearer test-uid:${firebaseUid1}` };
  const otherAuthHeader = { Authorization: `Bearer test-uid:${firebaseUid2}` };

  beforeAll(async () => {
    process.env.PLUGGY_WEBHOOK_SECRET = 'test-webhook-secret';

    const moduleRef: TestingModule = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(FIREBASE_ADMIN)
      .useValue(buildFakeFirebaseAdmin())
      .overrideProvider(PluggyApiClient)
      .useValue(buildFakePluggyApiClient())
      .compile();

    app = moduleRef.createNestApplication({ rawBody: true });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
    await app.init();
    prisma = moduleRef.get(PrismaService);
  });

  afterAll(async () => {
    for (const firebaseUid of [firebaseUid1, firebaseUid2]) {
      const user = await prisma.user.findUnique({ where: { firebaseUid } });
      if (user) {
        await prisma.financeAccount.deleteMany({ where: { conexao: { userId: user.id } } });
        await prisma.financeConnection.deleteMany({ where: { userId: user.id } });
        await prisma.boletoDda.deleteMany({ where: { userId: user.id } });
      }
    }
    await prisma.user.deleteMany({ where: { firebaseUid: { in: [firebaseUid1, firebaseUid2] } } });
    await app.close();
  });

  it('connects an institution, syncs via webhook, and computes saldo livre', async () => {
    await request(app.getHttpServer()).post('/users/me').set(authHeader).send({ nome: 'Usuário Finanças' }).expect(201);

    await request(app.getHttpServer())
      .post('/financas/conexoes')
      .set(authHeader)
      .send({ itemId: 'item-tenant-1' })
      .expect(201);

    const payload = { event: 'item/updated', itemId: 'item-tenant-1' };
    const rawBody = JSON.stringify(payload);
    const signature = createHmac('sha256', 'test-webhook-secret').update(rawBody).digest('hex');
    await request(app.getHttpServer())
      .post('/financas/webhooks/pluggy')
      .set('x-pluggy-signature', signature)
      .set('Content-Type', 'application/json')
      .send(rawBody)
      .expect(201);

    const resumo = await request(app.getHttpServer()).get('/financas/resumo').set(authHeader).expect(200);
    // saldo livre = 2000 (conta) - 500 (fatura aberta) - 100 (boleto dentro do ciclo, sem dia_recebimento = fim do mês) = 1400
    expect(resumo.body.saldoLivre).toBe(1400);
    expect(resumo.body.contas).toHaveLength(2);
    expect(resumo.body.boletos).toHaveLength(1);
  });

  it('does not leak finance data across tenants', async () => {
    await request(app.getHttpServer())
      .post('/users/me')
      .set(otherAuthHeader)
      .send({ nome: 'Outro Usuário' })
      .expect(201);
    await request(app.getHttpServer())
      .post('/financas/conexoes')
      .set(otherAuthHeader)
      .send({ itemId: 'item-tenant-2' })
      .expect(201);
    await request(app.getHttpServer()).post('/financas/sync').set(otherAuthHeader).expect(201);

    const tenant1Resumo = await request(app.getHttpServer()).get('/financas/resumo').set(authHeader).expect(200);
    const tenant2Resumo = await request(app.getHttpServer()).get('/financas/resumo').set(otherAuthHeader).expect(200);

    expect(tenant1Resumo.body.contas).toHaveLength(2);
    expect(tenant2Resumo.body.contas).toHaveLength(1);
    expect(tenant2Resumo.body.boletos).toHaveLength(0);
  });

  it("disconnecting one tenant's connection wipes only that tenant's data", async () => {
    const conexoes = await request(app.getHttpServer()).get('/financas/conexoes').set(authHeader).expect(200);
    const connectionId = conexoes.body[0].id;

    await request(app.getHttpServer()).delete(`/financas/conexoes/${connectionId}`).set(authHeader).expect(200);

    const resumoAfter = await request(app.getHttpServer()).get('/financas/resumo').set(authHeader).expect(200);
    expect(resumoAfter.body.contas).toHaveLength(0);
    expect(resumoAfter.body.boletos).toHaveLength(0);

    const tenant2Resumo = await request(app.getHttpServer()).get('/financas/resumo').set(otherAuthHeader).expect(200);
    expect(tenant2Resumo.body.contas).toHaveLength(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && npx jest --config ./test/jest-e2e.json finance-flow`
Expected: FAIL (routes/module wiring incomplete, or `buildFakePluggyApiClient` type mismatch) — confirm the failure is about the test infra, not a typo, before moving on.

- [ ] **Step 3: Fix any wiring gaps found while running the test**

At this point all production code already exists from Tasks 1–8; this step is about reconciling any mismatch surfaced by actually exercising the full stack together (e.g. a module not imported into `AppModule`, a select/response shape mismatch). Re-run after each fix.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && npx jest --config ./test/jest-e2e.json finance-flow`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/test
git commit -m "test: add e2e coverage for the finance connect, sync, resumo, and disconnect flow"
```

---

## Task 10: Finance connection repository, Pluggy Connect WebView, and Home card

**Files:**
- Create: `mobile/lib/features/financas/finance_connection.dart`
- Create: `mobile/lib/features/financas/finance_connection_repository.dart`
- Create: `mobile/lib/features/financas/finance_providers.dart`
- Create: `mobile/lib/features/financas/pluggy_connect_webview_screen.dart`
- Modify: `mobile/lib/features/home/home_screen.dart`
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/test/features/financas/finance_connection_repository_test.dart`

**Interfaces:**
- Consumes: `apiClientProvider` (existing, `mobile/lib/core/api_providers.dart`).
- Produces: `FinanceConnection { id, instituicao, status }`, `FinanceConnectionRepository` with `createConnectToken()`, `finalizeConnection(itemId)`, `listConnections()`, `disconnect(connectionId)`; providers `financeConnectionRepositoryProvider`, `financeConnectionsProvider`. Consumed by Task 11 (summary screen) and Task 13 (Settings).

- [ ] **Step 1: Write the failing test**

Create `mobile/test/features/financas/finance_connection_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_connection_repository.dart';

void main() {
  test('createConnectToken posts to /financas/connect-token and returns the token', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'connectToken': 'token-abc'}));
    }));

    final repository = FinanceConnectionRepository(dio);
    final token = await repository.createConnectToken();

    expect(capturedPath, '/financas/connect-token');
    expect(token, 'token-abc');
  });

  test('finalizeConnection posts the itemId and parses the connection', () async {
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'id': 'conn-1', 'instituicao': 'Banco Teste', 'status': 'UPDATED'},
      ));
    }));

    final repository = FinanceConnectionRepository(dio);
    final connection = await repository.finalizeConnection('item-1');

    expect(capturedData, {'itemId': 'item-1'});
    expect(connection.id, 'conn-1');
    expect(connection.instituicao, 'Banco Teste');
  });

  test('listConnections parses a list of connections', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {'id': 'conn-1', 'instituicao': 'Banco Teste', 'status': 'UPDATED'},
        ],
      ));
    }));

    final repository = FinanceConnectionRepository(dio);
    final connections = await repository.listConnections();

    expect(connections, hasLength(1));
    expect(connections.first.instituicao, 'Banco Teste');
  });

  test('disconnect calls the delete endpoint with the connection id', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));

    final repository = FinanceConnectionRepository(dio);
    await repository.disconnect('conn-1');

    expect(capturedPath, '/financas/conexoes/conn-1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/financas/finance_connection_repository_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'sincro_mobile/features/financas/finance_connection_repository.dart'`

- [ ] **Step 3: Write minimal implementation**

Add `webview_flutter` to `mobile/pubspec.yaml` (in `dependencies:`, after `firebase_messaging`):

```yaml
  webview_flutter: ^4.10.0
```

Run `cd mobile && flutter pub get` after adding it.

Create `mobile/lib/features/financas/finance_connection.dart`:

```dart
class FinanceConnection {
  const FinanceConnection({required this.id, required this.instituicao, required this.status});

  final String id;
  final String instituicao;
  final String status;

  factory FinanceConnection.fromJson(Map<String, dynamic> json) {
    return FinanceConnection(
      id: json['id'] as String,
      instituicao: json['instituicao'] as String,
      status: json['status'] as String,
    );
  }
}
```

Create `mobile/lib/features/financas/finance_connection_repository.dart`:

```dart
import 'package:dio/dio.dart';
import 'finance_connection.dart';

class FinanceConnectionRepository {
  FinanceConnectionRepository(this._dio);

  final Dio _dio;

  Future<String> createConnectToken() async {
    final response = await _dio.post('/financas/connect-token');
    return (response.data as Map<String, dynamic>)['connectToken'] as String;
  }

  Future<FinanceConnection> finalizeConnection(String itemId) async {
    final response = await _dio.post('/financas/conexoes', data: {'itemId': itemId});
    return FinanceConnection.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<FinanceConnection>> listConnections() async {
    final response = await _dio.get('/financas/conexoes');
    return (response.data as List)
        .map((e) => FinanceConnection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> disconnect(String connectionId) async {
    await _dio.delete('/financas/conexoes/$connectionId');
  }
}
```

Create `mobile/lib/features/financas/finance_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'finance_connection.dart';
import 'finance_connection_repository.dart';

final financeConnectionRepositoryProvider = Provider<FinanceConnectionRepository>((ref) {
  return FinanceConnectionRepository(ref.watch(apiClientProvider).dio);
});

final financeConnectionsProvider = FutureProvider.autoDispose<List<FinanceConnection>>((ref) {
  return ref.watch(financeConnectionRepositoryProvider).listConnections();
});
```

Create `mobile/lib/features/financas/pluggy_connect_webview_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _pluggyConnectBaseUrl = 'https://connect.pluggy.ai';
const _pluggyRedirectPrefix = 'https://sincro.app/pluggy-callback';

/// Hosts the Pluggy Connect widget in-app so the user never visually leaves Sincro. Completion is
/// detected via navigation to our own redirect URL (carrying `itemId` as a query param) rather
/// than a JS postMessage bridge, since intercepting navigation is a stable webview_flutter
/// feature regardless of exactly how Pluggy's widget JS communicates completion.
class PluggyConnectWebviewScreen extends StatefulWidget {
  const PluggyConnectWebviewScreen({super.key, required this.connectToken});

  final String connectToken;

  @override
  State<PluggyConnectWebviewScreen> createState() => _PluggyConnectWebviewScreenState();
}

class _PluggyConnectWebviewScreenState extends State<PluggyConnectWebviewScreen> {
  late final WebViewController _controller;
  bool _authBlocked = false;

  Uri get _connectUrl => Uri.parse(
        '$_pluggyConnectBaseUrl/?connectToken=${widget.connectToken}&redirectUrl=$_pluggyRedirectPrefix',
      );

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.startsWith(_pluggyRedirectPrefix)) {
              final itemId = Uri.parse(request.url).queryParameters['itemId'];
              if (itemId != null) {
                Navigator.of(context).pop(itemId);
              } else {
                setState(() => _authBlocked = true);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (_) => setState(() => _authBlocked = true),
        ),
      )
      ..loadRequest(_connectUrl);
  }

  Future<void> _openInExternalBrowser() async {
    if (await canLaunchUrl(_connectUrl)) {
      await launchUrl(_connectUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar conta'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: _authBlocked
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Este banco não permite login dentro do app. Você pode continuar num navegador.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _openInExternalBrowser, child: const Text('Abrir no navegador')),
                  ],
                ),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
```

Update `mobile/lib/features/home/home_screen.dart`:
- Add imports: `import '../financas/finance_connection.dart';`, `import '../financas/finance_providers.dart';`, `import '../financas/pluggy_connect_webview_screen.dart';`.
- In `_HomeScreenState.build`, add `final financeConnectionsAsync = ref.watch(financeConnectionsProvider);` and remove the line `const Text('Finanças chegam em breve.'),` — replace it with `_FinancasCard(connectionsAsync: financeConnectionsAsync),` right after `_GmailCard(...)`.
- Add this new widget class at the end of the file (after `_GmailCard`):

```dart
class _FinancasCard extends ConsumerWidget {
  const _FinancasCard({required this.connectionsAsync});

  final AsyncValue<List<FinanceConnection>> connectionsAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    try {
      final connectToken = await ref.read(financeConnectionRepositoryProvider).createConnectToken();
      if (!context.mounted) return;
      final itemId = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => PluggyConnectWebviewScreen(connectToken: connectToken)),
      );
      if (itemId == null) return;
      await ref.read(financeConnectionRepositoryProvider).finalizeConnection(itemId);
      ref.invalidate(financeConnectionsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível conectar sua conta. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return connectionsAsync.when(
      data: (connections) {
        if (connections.isEmpty) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('💰 Finanças'),
              subtitle: const Text('Conecte uma conta para ver seu saldo livre.'),
              trailing: ElevatedButton(
                onPressed: () => _connect(context, ref),
                child: const Text('Conectar conta'),
              ),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('💰 Finanças'),
            subtitle: Text('${connections.length} conta(s) conectada(s)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/financas'),
          ),
        );
      },
      loading: () => const Card(child: ListTile(title: Text('💰 Finanças'), subtitle: Text('Carregando...'))),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/financas/finance_connection_repository_test.dart`
Expected: PASS (4 tests)

Then manually verify (not covered by automated tests — `webview_flutter` needs platform channels unavailable in `flutter test`): run the app, tap "Conectar conta" on the Home card, confirm the WebView opens with a URL containing the connect token, and confirm the "abrir no navegador" fallback button appears if `onWebResourceError` fires.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/financas mobile/lib/features/home/home_screen.dart mobile/pubspec.yaml mobile/pubspec.lock mobile/test/features/financas
git commit -m "feat: add Pluggy Connect WebView flow and Finanças Home card"
```

---

## Task 11: Finance summary screen

**Files:**
- Create: `mobile/lib/features/financas/finance_summary.dart`
- Create: `mobile/lib/features/financas/finance_summary_repository.dart`
- Create: `mobile/lib/features/financas/financas_screen.dart`
- Modify: `mobile/lib/features/financas/finance_providers.dart`
- Modify: `mobile/lib/main.dart`
- Create: `mobile/test/features/financas/finance_summary_repository_test.dart`

**Interfaces:**
- Consumes: `apiClientProvider`; `GET /financas/resumo` and `POST /financas/sync` (Tasks 5, 6).
- Produces: `FinanceSummary { saldoLivre, contas, boletos }`, `FinanceSummaryRepository` with `getResumo()`/`sync()`; providers `financeSummaryRepositoryProvider`, `financeSummaryProvider`; `/financas` route.

- [ ] **Step 1: Write the failing test**

Create `mobile/test/features/financas/finance_summary_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_summary_repository.dart';

void main() {
  test('getResumo parses saldo livre, contas, and boletos', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'saldoLivre': 1400.0,
          'fimCiclo': '2026-08-31T00:00:00.000Z',
          'contas': [
            {
              'id': 'acc-1',
              'tipo': 'CORRENTE',
              'nome': 'Conta Corrente',
              'saldoOuFatura': 2000.0,
              'vencimentoFatura': null,
            },
          ],
          'boletos': [
            {'id': 'boleto-1', 'valor': 100.0, 'vencimento': '2026-08-05T00:00:00.000Z'},
          ],
        },
      ));
    }));

    final repository = FinanceSummaryRepository(dio);
    final summary = await repository.getResumo();

    expect(summary.saldoLivre, 1400.0);
    expect(summary.contas, hasLength(1));
    expect(summary.contas.first.nome, 'Conta Corrente');
    expect(summary.boletos, hasLength(1));
    expect(summary.boletos.first.valor, 100.0);
  });

  test('sync posts to /financas/sync', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'success': true}));
    }));

    final repository = FinanceSummaryRepository(dio);
    await repository.sync();

    expect(capturedPath, '/financas/sync');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/financas/finance_summary_repository_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'sincro_mobile/features/financas/finance_summary_repository.dart'`

- [ ] **Step 3: Write minimal implementation**

Create `mobile/lib/features/financas/finance_summary.dart`:

```dart
class FinanceAccountSummary {
  const FinanceAccountSummary({
    required this.id,
    required this.tipo,
    required this.nome,
    required this.saldoOuFatura,
    this.vencimentoFatura,
  });

  final String id;
  final String tipo;
  final String nome;
  final double saldoOuFatura;
  final DateTime? vencimentoFatura;

  factory FinanceAccountSummary.fromJson(Map<String, dynamic> json) {
    return FinanceAccountSummary(
      id: json['id'] as String,
      tipo: json['tipo'] as String,
      nome: json['nome'] as String,
      saldoOuFatura: (json['saldoOuFatura'] as num).toDouble(),
      vencimentoFatura:
          json['vencimentoFatura'] != null ? DateTime.parse(json['vencimentoFatura'] as String) : null,
    );
  }
}

class BoletoSummary {
  const BoletoSummary({required this.id, required this.valor, required this.vencimento});

  final String id;
  final double valor;
  final DateTime vencimento;

  factory BoletoSummary.fromJson(Map<String, dynamic> json) {
    return BoletoSummary(
      id: json['id'] as String,
      valor: (json['valor'] as num).toDouble(),
      vencimento: DateTime.parse(json['vencimento'] as String),
    );
  }
}

class FinanceSummary {
  const FinanceSummary({required this.saldoLivre, required this.contas, required this.boletos});

  final double saldoLivre;
  final List<FinanceAccountSummary> contas;
  final List<BoletoSummary> boletos;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      saldoLivre: (json['saldoLivre'] as num).toDouble(),
      contas: (json['contas'] as List)
          .map((e) => FinanceAccountSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      boletos:
          (json['boletos'] as List).map((e) => BoletoSummary.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
```

Create `mobile/lib/features/financas/finance_summary_repository.dart`:

```dart
import 'package:dio/dio.dart';
import 'finance_summary.dart';

class FinanceSummaryRepository {
  FinanceSummaryRepository(this._dio);

  final Dio _dio;

  Future<FinanceSummary> getResumo() async {
    final response = await _dio.get('/financas/resumo');
    return FinanceSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> sync() async {
    await _dio.post('/financas/sync');
  }
}
```

Update `mobile/lib/features/financas/finance_providers.dart` — add:

```dart
import 'finance_summary.dart';
import 'finance_summary_repository.dart';

final financeSummaryRepositoryProvider = Provider<FinanceSummaryRepository>((ref) {
  return FinanceSummaryRepository(ref.watch(apiClientProvider).dio);
});

final financeSummaryProvider = FutureProvider.autoDispose<FinanceSummary>((ref) {
  return ref.watch(financeSummaryRepositoryProvider).getResumo();
});
```

Create `mobile/lib/features/financas/financas_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'finance_providers.dart';
import 'finance_summary.dart';

class FinancasScreen extends ConsumerWidget {
  const FinancasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(financeSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Finanças')),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(financeSummaryRepositoryProvider).sync();
          } catch (_) {
            // Sync sob demanda é best-effort: se falhar, ainda mostramos os dados em cache.
          }
          ref.invalidate(financeSummaryProvider);
        },
        child: summaryAsync.when(
          data: (summary) => _FinancasContent(summary: summary),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Não foi possível carregar suas finanças. Puxe para tentar novamente.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemAVencer {
  const _ItemAVencer({required this.nome, required this.valor, required this.vencimento});

  final String nome;
  final double valor;
  final DateTime vencimento;
}

class _FinancasContent extends StatelessWidget {
  const _FinancasContent({required this.summary});

  final FinanceSummary summary;

  // Tom não punitivo: sem cor de alarme, e "venceu há X dia(s)" em vez de "atrasado".
  String _formatVencimento(DateTime vencimento) {
    final hoje = DateTime.now();
    final diasRestantes = DateTime(vencimento.year, vencimento.month, vencimento.day)
        .difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;
    if (diasRestantes < 0) return 'venceu há ${-diasRestantes} dia(s)';
    if (diasRestantes == 0) return 'vence hoje';
    return 'vence em $diasRestantes dia(s)';
  }

  @override
  Widget build(BuildContext context) {
    final itensAVencer = <_ItemAVencer>[
      ...summary.boletos.map((b) => _ItemAVencer(nome: 'Boleto', valor: b.valor, vencimento: b.vencimento)),
      ...summary.contas
          .where((c) => c.tipo == 'CARTAO_CREDITO' && c.vencimentoFatura != null)
          .map((c) => _ItemAVencer(nome: c.nome, valor: c.saldoOuFatura, vencimento: c.vencimentoFatura!)),
    ]..sort((a, b) => a.vencimento.compareTo(b.vencimento));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saldo livre', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  'R\$ ${summary.saldoLivre.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Contas conectadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ...summary.contas.map(
          (conta) => Card(
            child: ListTile(
              title: Text(conta.nome),
              subtitle: Text(conta.tipo),
              trailing: Text('R\$ ${conta.saldoOuFatura.toStringAsFixed(2)}'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('A vencer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (itensAVencer.isEmpty)
          const Padding(padding: EdgeInsets.all(8), child: Text('Nada por aqui. 🌿')),
        ...itensAVencer.map(
          (item) => Card(
            child: ListTile(
              title: Text(item.nome),
              subtitle: Text(_formatVencimento(item.vencimento)),
              trailing: Text('R\$ ${item.valor.toStringAsFixed(2)}'),
            ),
          ),
        ),
      ],
    );
  }
}
```

Update `mobile/lib/main.dart` — add the import `import 'features/financas/financas_screen.dart';` and the route entry `'/financas': (_) => const FinancasScreen(),` inside the `routes` map (after `'/inbox'`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/financas/finance_summary_repository_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/financas mobile/lib/main.dart mobile/test/features/financas
git commit -m "feat: add finance summary screen with saldo livre and upcoming bills"
```

---

## Task 12: Settings — dia de recebimento and per-connection disconnect

**Files:**
- Create: `mobile/lib/features/financas/dia_recebimento_repository.dart`
- Modify: `mobile/lib/features/financas/finance_providers.dart`
- Modify: `mobile/lib/features/settings/settings_screen.dart`
- Create: `mobile/test/features/financas/dia_recebimento_repository_test.dart`

**Interfaces:**
- Consumes: `PATCH /users/me/dia-recebimento` (Task 7); `financeConnectionsProvider`/`financeConnectionRepositoryProvider.disconnect` (Task 10).
- Produces: `DiaRecebimentoRepository.update(int? diaRecebimento)`; `diaRecebimentoRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

Create `mobile/test/features/financas/dia_recebimento_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/dia_recebimento_repository.dart';

void main() {
  test('update sends the chosen day to the backend', () async {
    String? capturedPath;
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));

    final repository = DiaRecebimentoRepository(dio);
    await repository.update(15);

    expect(capturedPath, '/users/me/dia-recebimento');
    expect(capturedData, {'diaRecebimento': 15});
  });

  test('update sends null to clear the day', () async {
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));

    final repository = DiaRecebimentoRepository(dio);
    await repository.update(null);

    expect(capturedData, {'diaRecebimento': null});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/financas/dia_recebimento_repository_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'sincro_mobile/features/financas/dia_recebimento_repository.dart'`

- [ ] **Step 3: Write minimal implementation**

Create `mobile/lib/features/financas/dia_recebimento_repository.dart`:

```dart
import 'package:dio/dio.dart';

class DiaRecebimentoRepository {
  DiaRecebimentoRepository(this._dio);

  final Dio _dio;

  Future<void> update(int? diaRecebimento) async {
    await _dio.patch('/users/me/dia-recebimento', data: {'diaRecebimento': diaRecebimento});
  }
}
```

Update `mobile/lib/features/financas/finance_providers.dart` — add:

```dart
import 'dia_recebimento_repository.dart';

final diaRecebimentoRepositoryProvider = Provider<DiaRecebimentoRepository>((ref) {
  return DiaRecebimentoRepository(ref.watch(apiClientProvider).dio);
});
```

Update `mobile/lib/features/settings/settings_screen.dart`:
- Add imports: `import '../financas/finance_connection.dart';`, `import '../financas/finance_providers.dart';`.
- Add these two methods inside `_SettingsScreenState` (alongside `_disconnectGmail`):

```dart
  Future<void> _editDiaRecebimento() async {
    final controller = TextEditingController();
    final result = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dia de recebimento'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Ex: 5 (dia 5 de cada mês)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, null), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result < 1 || result > 31) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um dia entre 1 e 31.')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(diaRecebimentoRepositoryProvider).update(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dia de recebimento salvo.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectFinanceConnection(FinanceConnection connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Desconectar ${connection.instituicao}?'),
        content: const Text('Os dados dessa conexão serão apagados. Você pode reconectar quando quiser.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(financeConnectionRepositoryProvider).disconnect(connection.id);
      ref.invalidate(financeConnectionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${connection.instituicao} desconectado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desconectar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

- Update `build()`: watch the connections and splice their tiles into the list.

```dart
  @override
  Widget build(BuildContext context) {
    final connectionsAsync = ref.watch(financeConnectionsProvider);
    final financeConnectionTiles = connectionsAsync.maybeWhen(
      data: (connections) => connections
          .map(
            (c) => ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text('Desconectar ${c.instituicao}'),
              onTap: _busy ? null : () => _disconnectFinanceConnection(c),
            ),
          )
          .toList(),
      orElse: () => <Widget>[],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar perfil sensorial'),
            onTap: _busy ? null : _editSensoryProfile,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Apagar perfil sensorial'),
            onTap: _busy ? null : _deleteSensoryProfile,
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Gerenciar contatos de confiança'),
            onTap: _busy ? null : _manageContacts,
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Desconectar Gmail'),
            onTap: _busy ? null : _disconnectGmail,
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Definir dia de recebimento'),
            onTap: _busy ? null : _editDiaRecebimento,
          ),
          ...financeConnectionTiles,
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sair'),
            onTap: _busy ? null : _signOut,
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/financas/dia_recebimento_repository_test.dart`
Expected: PASS (2 tests)

Then run the full mobile test suite to confirm nothing else broke: `cd mobile && flutter test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/financas mobile/lib/features/settings/settings_screen.dart mobile/test/features/financas
git commit -m "feat: add dia de recebimento setting and per-connection disconnect"
```

---

## Plan Self-Review Notes

**Spec coverage:**
- Conectar múltiplas instituições (WebView) → Task 3 (backend), Task 10 (mobile).
- Ver saldo livre e contas conectadas → Task 6 (backend), Task 11 (mobile).
- Ver boletos/faturas a vencer → Task 6, Task 11.
- Notificação agregada não punitiva (3 dias, `toleranciaNotificacao`) → Task 8.
- Definir/editar dia de recebimento → Task 7 (backend), Task 12 (mobile).
- Desconectar e apagar dados derivados → Task 3 (backend disconnect logic), Task 12 (mobile UI).
- Sincronização via webhook + sob demanda → Task 5.
- Segurança/LGPD (sem credenciais bancárias armazenadas, tenant isolation, assinatura do webhook) → Tasks 3, 5, 9 (raw-body HMAC verification, `userId`-scoped queries throughout).

**Known limitation carried over from the e-mail pillar:** `HORARIO_ESPECIFICO` tolerance is treated as silent in `notifyContasVencendo` (Task 8), same as `notifyNewEmailsNeedAttention` — the anamnese never collected an actual time window, so there's no way to know if "now" is inside it.

**Type consistency check:** `PluggyAccount.type` (`'BANK' | 'CREDIT'`) maps to `FinanceAccount.tipo` (`'CORRENTE' | 'CARTAO_CREDITO'`) consistently in Task 4's `FinanceSyncService` and is read back with the same string values in Task 6's calculator and Task 8's scheduler (`tipo === 'CARTAO_CREDITO'`) and in the mobile `FinanceAccountSummary`/`FinancasScreen` (`tipo == 'CARTAO_CREDITO'`). `notificadoEm` exists on both `BoletoDda` and `FinanceAccount` (Task 1) and is read/written consistently by Task 8's scheduler.

**Deferred (explicitly out of scope, from the approved spec):**
- Iniciar pagamento de boleto pelo app.
- Categorização de gastos / orçamento.
- Previsão de gastos recorrentes sem boleto/fatura associado.
- Diferenciação por `plano`.
- Dados de investimento via Pluggy.
- Janela de alerta configurável (fixa em 3 dias nesta fase).
