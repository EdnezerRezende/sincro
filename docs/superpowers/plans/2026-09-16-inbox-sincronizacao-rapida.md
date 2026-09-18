# Caixa de Entrada — sincronização rápida com o Gmail — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** uma mensagem que chega no Gmail aparece no app em até 2 minutos sem ação do usuário; ao conectar, a caixa é preenchida em segundos; a aba Atualizações passa a entrar; a lista deixa de cortar em 100.

**Architecture:** o único gatilho (cron de 20 min) vira três (cron de 2 min com lock por usuário, evento `gmail.conectado` emitido pelo controller e escutado pelo scheduler, endpoint manual com debounce). Os filtros do `GmailApiClient` mudam (Atualizações entra, `INBOX` obrigatório, sync inicial de 30 dias paginada, `history.list` paginado). O backend avisa o app com FCM só de dados; o app invalida a lista ao receber, ao voltar ao primeiro plano e ao puxar para atualizar; a listagem ganha paginação por cursor com compatibilidade para o app em campo.

**Tech Stack:** NestJS 11 (+ `@nestjs/event-emitter`, novo), Prisma 7, googleapis, firebase-admin; Flutter + flutter_riverpod 3.3.2 + dio + firebase_messaging; Jest, flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-16-inbox-sincronizacao-rapida-design.md` — o plano argumenta a partir dela; executores leem ambos.

## Global Constraints

- Uma réplica do backend (lock em memória é suficiente).
- Só o endpoint manual aplica o debounce de 30 s; o cron e o evento de conexão **nunca**.
- FCM de dados (`tipo: 'inbox_atualizada'`) é enviado **só** pelos chamadores agendados (cron e evento); o endpoint manual não envia.
- `GET /resumos-email` **sem** `cursor` nem `limite` devolve o array dos 100 mais recentes exatamente como hoje (compatibilidade com o app 1.0.12 (5) e com os e2e `email-triage-flow`/`email-reply-flow`).
- `NOISE_LABELS` final: `CATEGORY_PROMOTIONS`, `CATEGORY_SOCIAL`, `CATEGORY_FORUMS`, `SPAM`. Mensagem sem `INBOX` em `labelIds` é descartada nos dois caminhos.
- Cópias de UI existentes não mudam: "Nenhum e-mail novo por aqui.", "Não foi possível conectar o Gmail. Tente novamente.", "Não foi possível reconectar. Tente novamente.", "Gmail não conectado.".
- Helper `conectarGmail(ref)` relança erros e só invalida providers se `ref.context.mounted`.
- Commits em português na branch `feat/inbox-sincronizacao-rapida`, com `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Backend: `cd backend && npm test -- <paths>` (o script já define `NODE_OPTIONS=--experimental-vm-modules`); `npx tsc --noEmit -p tsconfig.json`. Mobile: `cd mobile && flutter test <paths>` e `flutter analyze` nos arquivos tocados.

## File Structure

| Arquivo | Responsabilidade |
|---------|------------------|
| `backend/src/email-sync/email-sync-lock.service.ts` (novo) | lock por usuário em memória |
| `backend/src/gmail/gmail-api-client.service.ts` | `NOISE_LABELS`, `INBOX`, `fetchInitial` paginado, `fetchIncremental` paginado |
| `backend/src/email-sync/email-sync.service.ts` | `syncUser` → `{ novos, novosPrecisamAtencao }`, `listarLegado`, `listarPagina`, cursor |
| `backend/prisma/schema.prisma` + migration `add_email_summary_cursor_index` | índice `(userId, recebidoEm desc, id desc)` |
| `backend/src/notifications/notification.service.ts` | `notifyInboxAtualizada` |
| `backend/src/email-sync/email-sync.scheduler.ts` | cron `*/2`, lock, FCM de dados, `@OnEvent('gmail.conectado')` |
| `backend/src/gmail/events/gmail-conectado.event.ts` (novo) | `GmailConectadoEvent` |
| `backend/src/gmail/gmail.controller.ts` | emite `gmail.conectado` |
| `backend/src/gmail/gmail-connections.service.ts` | zera `lastHistoryId` ao reconectar; `status()` com `ultimaSincronizacao` |
| `backend/src/app.module.ts` | `EventEmitterModule.forRoot()` |
| `backend/src/email-sync/email-summary.controller.ts` | `GET` compat/paginado; `POST /sincronizar` |
| `mobile/lib/core/revalidation.dart` (novo) | `kRevalidationMinInterval` |
| `mobile/lib/features/calendar/calendar_screen.dart` | importa a constante compartilhada |
| `mobile/lib/features/email_triage/gmail_connection_repository.dart` | `ultimaSincronizacao` |
| `mobile/lib/features/email_triage/email_summary_repository.dart` | `listar({cursor, limite})`, `sincronizar()` |
| `mobile/lib/features/email_triage/email_triage_providers.dart` | `EmailSummariesNotifier` |
| `mobile/lib/features/email_triage/inbox_screen.dart` | pull-to-refresh com sync, "Carregar mais", `resumed`, estado "Sincronizando…" |
| `mobile/lib/features/email_triage/gmail_connection_actions.dart` | `conectarGmail(ref)`; `reconectarGmail*` usam-no |
| `mobile/lib/features/home/home_screen.dart`, `calendar/calendar_screen.dart`, `email_triage/email_detail_screen.dart` | usam `conectarGmail(ref)` |
| `mobile/lib/main.dart` | `ProviderContainer` global, `onMessage` |

Grafo de dependências: T1, T2, T4, T7 independentes → T3 (após T2), T8 (após T7) → T5 (após T1, T3, T4), T9 (após T8) → T6 (após T3, T5) → T10.

---

### Task 1: `EmailSyncLockService`

**Files:**
- Create: `backend/src/email-sync/email-sync-lock.service.ts`, `backend/src/email-sync/email-sync-lock.service.spec.ts`
- Modify: `backend/src/email-sync/email-sync.module.ts` (providers + exports)

**Interfaces:**
- Produces: `class EmailSyncLockService { executar<T>(userId: string, fn: () => Promise<T>): Promise<T | null> }` — devolve `null` quando o usuário já está em execução; libera no `finally`.

- [ ] **Step 1: Teste**

```ts
import { EmailSyncLockService } from './email-sync-lock.service';

describe('EmailSyncLockService', () => {
  it('executa a função e devolve o resultado', async () => {
    const lock = new EmailSyncLockService();
    await expect(lock.executar('u1', async () => 42)).resolves.toBe(42);
  });

  it('devolve null quando o mesmo usuário já está em execução', async () => {
    const lock = new EmailSyncLockService();
    let resolver!: () => void;
    const primeira = lock.executar('u1', () => new Promise<string>((r) => { resolver = () => r('ok'); }));
    await expect(lock.executar('u1', async () => 'segunda')).resolves.toBeNull();
    resolver();
    await expect(primeira).resolves.toBe('ok');
  });

  it('usuários diferentes correm em paralelo', async () => {
    const lock = new EmailSyncLockService();
    let resolver!: () => void;
    const lenta = lock.executar('u1', () => new Promise<string>((r) => { resolver = () => r('u1'); }));
    await expect(lock.executar('u2', async () => 'u2')).resolves.toBe('u2');
    resolver();
    await lenta;
  });

  it('libera o lock após erro', async () => {
    const lock = new EmailSyncLockService();
    await expect(lock.executar('u1', async () => { throw new Error('boom'); })).rejects.toThrow('boom');
    await expect(lock.executar('u1', async () => 'de novo')).resolves.toBe('de novo');
  });
});
```

- [ ] **Step 2:** `cd backend && npm test -- src/email-sync/email-sync-lock.service.spec.ts` → FAIL (módulo não encontrado).

- [ ] **Step 3: Implementar**

```ts
import { Injectable } from '@nestjs/common';

/** Lock POR USUÁRIO, em memória (premissa: uma réplica). Substitui o guard global `running` do
 *  scheduler: um usuário lento (reprocessamento de finanças, PDF) não segura os outros, e o mesmo
 *  usuário nunca sincroniza em paralelo (cron × endpoint manual × evento de conexão). */
@Injectable()
export class EmailSyncLockService {
  private readonly emExecucao = new Set<string>();

  /** Executa `fn` se o usuário não estiver em sincronização; devolve `null` se pulou. */
  async executar<T>(userId: string, fn: () => Promise<T>): Promise<T | null> {
    if (this.emExecucao.has(userId)) return null;
    this.emExecucao.add(userId);
    try {
      return await fn();
    } finally {
      this.emExecucao.delete(userId);
    }
  }
}
```

Em `email-sync.module.ts`: `providers: [EmailSyncService, EmailSyncScheduler, EmailSyncLockService]`, `exports: [EmailSyncService, EmailSyncLockService]`.

- [ ] **Step 4:** teste → PASS. `npx tsc --noEmit -p tsconfig.json` limpo.
- [ ] **Step 5: Commit** — `feat(email-sync): lock de sincronização por usuário`

---

### Task 2: Filtros e paginação do `GmailApiClient`

**Files:**
- Modify: `backend/src/gmail/gmail-api-client.service.ts` (`NOISE_LABELS` ~58-64; `fetchInitialUnread` ~120-138 → `fetchInitial`; `fetchIncremental` ~145-180; `fetchMessages` ~197)
- Modify: `backend/src/gmail/gmail-api-client.service.spec.ts`
- Modify: `backend/src/email-sync/email-sync.service.ts` (só as duas chamadas `fetchInitialUnread` → `fetchInitial`, ~linhas 304 e 319) e `backend/src/email-sync/email-sync.service.spec.ts` (renomear o mock `fetchInitialUnread` → `fetchInitial`)
- Modify: `backend/test/support/fake-gmail-api-client.ts` (renomear o método do fake)

**Interfaces:**
- Produces: `fetchInitial(refreshToken: string): Promise<{ emails: FetchedEmail[]; historyId: string | null }>` (substitui `fetchInitialUnread`); `fetchIncremental` mantém a assinatura; `fetchMessages` descarta `NOISE_LABELS` **e** ausência de `INBOX`.

- [ ] **Step 1: Testes** (usar a fábrica de mock `google.gmail` já existente no spec; acrescentar contadores de chamadas e `nextPageToken`)

```ts
describe('fetchInitial', () => {
  it('busca 30 dias, lidas e não lidas, sem excluir Atualizações, e pagina até 200 ids', async () => {
    // mock: messages.list devolve 100 ids + nextPageToken 'p2' na 1ª chamada, 100 ids na 2ª
    const { client, mocks } = clientComLista([{ ids: 100, nextPageToken: 'p2' }, { ids: 100 }]);
    const r = await client.fetchInitial('rt');
    const q = mocks.list.mock.calls[0][0].q as string;
    expect(q).toContain('in:inbox');
    expect(q).not.toContain('is:unread');
    expect(q).not.toContain('-category:updates');
    expect(q).toContain('-category:promotions -category:social -category:forums');
    expect(mocks.list.mock.calls[0][0].maxResults).toBe(100);
    expect(mocks.list.mock.calls[1][0].pageToken).toBe('p2');
    expect(mocks.get).toHaveBeenCalledTimes(200);
    expect(r.historyId).toBe('h-profile');
  });
  it('para em 200 mesmo com mais páginas', async () => {
    const { client, mocks } = clientComLista([{ ids: 100, nextPageToken: 'p2' }, { ids: 100, nextPageToken: 'p3' }, { ids: 100 }]);
    await client.fetchInitial('rt');
    expect(mocks.list).toHaveBeenCalledTimes(2);
  });
  it('after cobre 30 dias', async () => {
    const antes = Math.floor((Date.now() - 30 * 24 * 3600 * 1000) / 1000);
    const { client, mocks } = clientComLista([{ ids: 1 }]);
    await client.fetchInitial('rt');
    const m = (mocks.list.mock.calls[0][0].q as string).match(/after:(\d+)/);
    expect(Number(m![1])).toBeGreaterThanOrEqual(antes - 5);
  });
});

describe('fetchMessages — filtros', () => {
  it.each([
    [['INBOX', 'CATEGORY_UPDATES'], true],
    [['INBOX', 'CATEGORY_PROMOTIONS'], false],
    [['INBOX', 'CATEGORY_SOCIAL'], false],
    [['INBOX', 'CATEGORY_FORUMS'], false],
    [['INBOX', 'SPAM'], false],
    [['SENT'], false],
    [['CATEGORY_UPDATES'], false],
    [['INBOX'], true],
  ])('labelIds %p → mantida=%p (initial e incremental)', async (labels, mantida) => {
    const { client } = clientComMensagem({ labelIds: labels });
    const ini = await client.fetchInitial('rt');
    const inc = await client.fetchIncremental('rt', 'h0');
    expect(ini.emails).toHaveLength(mantida ? 1 : 0);
    expect(inc.emails).toHaveLength(mantida ? 1 : 0);
  });
});

describe('fetchIncremental — paginação', () => {
  it('segue nextPageToken e devolve o historyId da última página', async () => {
    const { client, mocks } = clientComHistory([
      { messagesAdded: ['m1'], historyId: 'h1', nextPageToken: 'p2' },
      { messagesAdded: ['m2'], historyId: 'h2' },
    ]);
    const r = await client.fetchIncremental('rt', 'h0');
    expect(r.emails.map((e) => e.gmailMessageId)).toEqual(['m1', 'm2']);
    expect(r.historyId).toBe('h2');
    expect(mocks.historyList.mock.calls[1][0].pageToken).toBe('p2');
  });
  it('404 continua virando historyExpired', async () => { /* já existe — manter */ });
});
```

Escreva `clientComLista`, `clientComMensagem`, `clientComHistory` no spec reaproveitando o `jest.mock('googleapis', …)` já existente: `list` devolve `{ data: { messages: ids.map((i)=>({id:`m${i}`})), nextPageToken } }`; `get` devolve `{ data: { id, labelIds, payload: { headers: [] }, snippet: '', internalDate: '1' } }`; `history.list` devolve `{ data: { history: [{ messagesAdded: ids.map((id)=>({ message: { id } })) }], historyId, nextPageToken } }`.

- [ ] **Step 2:** `npm test -- src/gmail/gmail-api-client.service.spec.ts` → FAIL.

- [ ] **Step 3: Implementar**

```ts
const NOISE_LABELS = new Set(['CATEGORY_PROMOTIONS', 'CATEGORY_SOCIAL', 'CATEGORY_FORUMS', 'SPAM']);
const INITIAL_DIAS = 30;
const INITIAL_MAX = 200;
const INITIAL_PAGE = 100;

/** Primeira sincronização (sem `lastHistoryId`) e fallback quando o historyId expira: caixa de
 *  entrada dos últimos 30 dias, lidas e não lidas, até 200 mensagens em páginas de 100. Atualizações
 *  entra (é onde o Gmail põe bancos e faturas); Promoções/Social/Fóruns continuam fora. */
async fetchInitial(refreshToken: string): Promise<{ emails: FetchedEmail[]; historyId: string | null }> {
  const gmail = this.gmailFor(refreshToken);
  const after = Math.floor((Date.now() - INITIAL_DIAS * 24 * 60 * 60 * 1000) / 1000);
  const ids: string[] = [];
  let pageToken: string | undefined;
  do {
    const list = await gmail.users.messages.list({
      userId: 'me',
      q: `in:inbox after:${after} -category:promotions -category:social -category:forums`,
      maxResults: INITIAL_PAGE,
      pageToken,
    });
    for (const m of list.data.messages ?? []) if (typeof m.id === 'string') ids.push(m.id);
    pageToken = list.data.nextPageToken ?? undefined;
  } while (pageToken && ids.length < INITIAL_MAX);
  const emails = await this.fetchMessages(gmail, ids.slice(0, INITIAL_MAX));
  const profile = await gmail.users.getProfile({ userId: 'me' });
  return { emails, historyId: profile.data.historyId ?? null };
}
```

`fetchIncremental`: envolver o `history.list` num `do … while (pageToken)` acumulando `messageIds` e guardando `ultimoHistoryId = history.data.historyId ?? ultimoHistoryId`; devolver `historyId: ultimoHistoryId ?? sinceHistoryId`. O `catch` do 404 permanece.

`fetchMessages`: após ler `labelIds`, `if (!labelIds.includes('INBOX') || labelIds.some((l) => NOISE_LABELS.has(l))) continue;`.

Atualizar o comentário de `NOISE_LABELS` (Atualizações deixa de ser ruído) e renomear as chamadas em `email-sync.service.ts` (`fetchInitialUnread` → `fetchInitial`, duas ocorrências) e o método do fake em `test/support/fake-gmail-api-client.ts`; em `email-sync.service.spec.ts` renomear a chave do mock `gmailApiClient`.

- [ ] **Step 4:** `npm test -- src/gmail src/email-sync` → PASS; `tsc` limpo.
- [ ] **Step 5: Commit** — `feat(gmail): Atualizações entra, INBOX obrigatório, sync inicial de 30 dias paginada e history.list paginado`

---

### Task 3: `syncUser` devolve `novos`; listagem por cursor; índice

**Files:**
- Modify: `backend/src/email-sync/email-sync.service.ts` (`syncUser` ~42-193; `list` ~322-342)
- Modify: `backend/src/email-sync/email-sync.service.spec.ts`
- Modify: `backend/prisma/schema.prisma` (model `EmailSummary`); Create: `backend/prisma/migrations/20260916120000_add_email_summary_cursor_index/migration.sql`

**Interfaces:**
- Produces: `syncUser(userId): Promise<{ novos: number; novosPrecisamAtencao: number }>`; `listarLegado(firebaseUid): Promise<ResumoEmailDto[]>` (idêntico ao `list()` atual); `listarPagina(firebaseUid, { cursor?: string; limite: number }): Promise<{ itens: ResumoEmailDto[]; proximoCursor: string | null }>`; `codificarCursor(recebidoEm: Date, id: string): string` e `decodificarCursor(cursor: string): { recebidoEm: Date; id: string }` (lança `BadRequestException('Cursor inválido.')`).

- [ ] **Step 1: Testes** (no spec existente, com o `buildDeps` atual)

```ts
describe('syncUser — novos', () => {
  it('conta só os create bem-sucedidos', async () => {
    const deps = buildDeps();
    deps.prisma.gmailConnection.findUnique.mockResolvedValue({ userId: 'u1', lastHistoryId: null });
    deps.gmailApiClient.fetchInitial.mockResolvedValue({ emails: [email('m1'), email('m2'), email('m3')], historyId: 'h1' });
    deps.prisma.emailSummary.create
      .mockResolvedValueOnce({})
      .mockRejectedValueOnce({ code: 'P2002' })
      .mockResolvedValueOnce({});
    const r = await buildService(deps).syncUser('u1');
    expect(r.novos).toBe(2);
  });
});

describe('listarLegado / listarPagina', () => {
  const linhas = (n: number) => Array.from({ length: n }, (_, i) => ({
    id: `id${String(9 - i).padStart(2, '0')}`, gmailMessageId: `g${i}`, remetente: 'r', assunto: 'a', resumoCurto: 's',
    categoria: 'PODE_ESPERAR', recebidoEm: new Date(Date.UTC(2026, 8, 1, 12, 0, 0)),
  }));
  it('listarLegado mantém o contrato atual (array, take 100, select fixo)', async () => {
    const deps = buildDeps(); deps.prisma.emailSummary.findMany.mockResolvedValue(linhas(2));
    const r = await buildService(deps).listarLegado('fb1');
    expect(Array.isArray(r)).toBe(true);
    expect(deps.prisma.emailSummary.findMany).toHaveBeenCalledWith(expect.objectContaining({ take: 100, orderBy: { recebidoEm: 'desc' } }));
  });
  it('listarPagina devolve limite itens e cursor do último quando há mais', async () => {
    const deps = buildDeps(); deps.prisma.emailSummary.findMany.mockResolvedValue(linhas(3)); // take = 2+1
    const r = await buildService(deps).listarPagina('fb1', { limite: 2 });
    expect(r.itens).toHaveLength(2);
    expect(r.proximoCursor).toBe(codificarCursor(r.itens[1].recebidoEm, r.itens[1].id));
    expect(deps.prisma.emailSummary.findMany).toHaveBeenCalledWith(expect.objectContaining({
      take: 3, orderBy: [{ recebidoEm: 'desc' }, { id: 'desc' }],
      select: expect.objectContaining({ id: true, gmailMessageId: true, remetente: true, assunto: true, resumoCurto: true, categoria: true, recebidoEm: true }),
    }));
  });
  it('proximoCursor é null na última página', async () => {
    const deps = buildDeps(); deps.prisma.emailSummary.findMany.mockResolvedValue(linhas(2));
    const r = await buildService(deps).listarPagina('fb1', { limite: 2 });
    expect(r.proximoCursor).toBeNull();
  });
  it('cursor aplica o filtro (recebidoEm, id) com recebidoEm igual', async () => {
    const deps = buildDeps(); deps.prisma.emailSummary.findMany.mockResolvedValue([]);
    const rec = new Date(Date.UTC(2026, 8, 1, 12));
    await buildService(deps).listarPagina('fb1', { limite: 50, cursor: codificarCursor(rec, 'id05') });
    expect(deps.prisma.emailSummary.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId: 'u1', OR: [{ recebidoEm: { lt: rec } }, { recebidoEm: rec, id: { lt: 'id05' } }] },
    }));
  });
  it('limite acima de 100 vira 100; abaixo de 1 vira 1', async () => {
    const deps = buildDeps(); deps.prisma.emailSummary.findMany.mockResolvedValue([]);
    await buildService(deps).listarPagina('fb1', { limite: 500 });
    expect(deps.prisma.emailSummary.findMany).toHaveBeenCalledWith(expect.objectContaining({ take: 101 }));
  });
  it('cursor malformado → 400 Cursor inválido.', async () => {
    await expect(buildService(buildDeps()).listarPagina('fb1', { limite: 50, cursor: '###' })).rejects.toThrow('Cursor inválido.');
  });
});
```

- [ ] **Step 2:** FAIL.

- [ ] **Step 3: Implementar**

```ts
const SELECT_RESUMO = { id: true, gmailMessageId: true, remetente: true, assunto: true, resumoCurto: true, categoria: true, recebidoEm: true } as const;
const LIMITE_MAX = 100;

export function codificarCursor(recebidoEm: Date, id: string): string {
  return Buffer.from(`${recebidoEm.toISOString()}|${id}`, 'utf8').toString('base64url');
}
export function decodificarCursor(cursor: string): { recebidoEm: Date; id: string } {
  const texto = Buffer.from(cursor, 'base64url').toString('utf8');
  const sep = texto.indexOf('|');
  const recebidoEm = sep > 0 ? new Date(texto.slice(0, sep)) : new Date(NaN);
  const id = sep > 0 ? texto.slice(sep + 1) : '';
  if (Number.isNaN(recebidoEm.getTime()) || !id) throw new BadRequestException('Cursor inválido.');
  return { recebidoEm, id };
}
```

`syncUser`: `let novos = 0;` incrementa logo após o `emailSummary.create` bem-sucedido (antes do `if (classification.categoria === 'PRECISA_ATENCAO')`); os dois `return` iniciais devolvem `{ novos: 0, novosPrecisamAtencao: 0 }`; o final `{ novos, novosPrecisamAtencao }`.

```ts
/** Contrato antigo: array dos 100 mais recentes. Usado quando o cliente não manda cursor/limite
 *  (app 1.0.12 (5) em campo e os e2e existentes). */
async listarLegado(firebaseUid: string) {
  const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
  return this.prisma.emailSummary.findMany({ where: { userId: user.id }, orderBy: { recebidoEm: 'desc' }, take: 100, select: SELECT_RESUMO });
}

async listarPagina(firebaseUid: string, opts: { cursor?: string; limite: number }) {
  const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
  const limite = Math.min(Math.max(Math.trunc(opts.limite) || 50, 1), LIMITE_MAX);
  const cursor = opts.cursor ? decodificarCursor(opts.cursor) : null;
  const linhas = await this.prisma.emailSummary.findMany({
    where: cursor
      ? { userId: user.id, OR: [{ recebidoEm: { lt: cursor.recebidoEm } }, { recebidoEm: cursor.recebidoEm, id: { lt: cursor.id } }] }
      : { userId: user.id },
    orderBy: [{ recebidoEm: 'desc' }, { id: 'desc' }],
    take: limite + 1,
    select: SELECT_RESUMO,
  });
  const itens = linhas.slice(0, limite);
  const ultimo = itens[itens.length - 1];
  return { itens, proximoCursor: linhas.length > limite && ultimo ? codificarCursor(ultimo.recebidoEm, ultimo.id) : null };
}
```

Remover `list()`; o controller passa a chamar `listarLegado` (Task 6 troca a chamada; nesta task troque a chamada existente em `email-summary.controller.ts:22` para `listarLegado` para compilar).

Prisma: em `model EmailSummary` acrescentar `@@index([userId, recebidoEm(sort: Desc), id(sort: Desc)])`; migration:

```sql
-- CreateIndex
CREATE INDEX "resumos_email_user_id_recebido_em_id_idx" ON "resumos_email"("user_id", "recebido_em" DESC, "id" DESC);
```
Verifique o nome que o Prisma gera com `npx prisma migrate diff --from-schema-datamodel <schema sem o índice> --to-schema-datamodel prisma/schema.prisma --script` (ou reproduza a convenção `<tabela>_<colunas>_idx`); use exatamente esse nome.

- [ ] **Step 4:** `npm test -- src/email-sync && npx prisma validate && npx tsc --noEmit -p tsconfig.json` → verdes. Atualizar testes existentes que esperavam `{ novosPrecisamAtencao }` puro (`toEqual` → incluir `novos`).
- [ ] **Step 5: Commit** — `feat(email-sync): syncUser devolve novos; listagem paginada por cursor com caminho legado`

---

### Task 4: `notifyInboxAtualizada`

**Files:**
- Modify: `backend/src/notifications/notification.service.ts`, `backend/src/notifications/notification.service.spec.ts`

**Interfaces:**
- Produces: `notifyInboxAtualizada(userId: string): Promise<void>` — nunca lança.

- [ ] **Step 1: Testes**

```ts
describe('notifyInboxAtualizada', () => {
  it('envia mensagem só de dados, sem notification e sem checar tolerância', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'tok' });
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);
    await service.notifyInboxAtualizada('u1');
    expect(sensoryProfileService.get).not.toHaveBeenCalled();
    expect(send).toHaveBeenCalledWith({
      token: 'tok',
      data: { tipo: 'inbox_atualizada' },
      android: { priority: 'high' },
      apns: { headers: { 'apns-push-type': 'background', 'apns-priority': '5' }, payload: { aps: { contentAvailable: true } } },
    });
    expect(send.mock.calls[0][0]).not.toHaveProperty('notification');
  });
  it('sem fcmToken não envia', async () => { /* findUnique → { fcmToken: null } → send não chamado */ });
  it('token inválido não propaga', async () => {
    const { firebaseAdmin, prisma, sensoryProfileService, send } = buildDeps();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', firebaseUid: 'fb1', fcmToken: 'tok' });
    send.mockRejectedValue(new Error('registration-token-not-registered'));
    const service = new NotificationService(firebaseAdmin as any, prisma as any, sensoryProfileService as any);
    await expect(service.notifyInboxAtualizada('u1')).resolves.toBeUndefined();
  });
});
```

- [ ] **Step 2:** FAIL. **Step 3:**

```ts
private readonly logger = new Logger(NotificationService.name);

/** Push SÓ DE DADOS: não aparece na bandeja, não é interrupção sensorial, por isso não passa pela
 *  tolerância da anamnese. O app, ao recebê-lo, apenas relê a caixa de entrada. */
async notifyInboxAtualizada(userId: string): Promise<void> {
  const user = await this.prisma.user.findUnique({ where: { id: userId } });
  if (!user?.fcmToken) return;
  try {
    await this.firebaseAdmin.messaging().send({
      token: user.fcmToken,
      data: { tipo: 'inbox_atualizada' },
      android: { priority: 'high' },
      apns: { headers: { 'apns-push-type': 'background', 'apns-priority': '5' }, payload: { aps: { contentAvailable: true } } },
    });
  } catch (error) {
    this.logger.warn(`FCM inbox_atualizada falhou para ${userId}: ${(error as Error).message}`);
  }
}
```

- [ ] **Step 4:** `npm test -- src/notifications` → PASS. **Step 5: Commit** — `feat(notifications): push só de dados inbox_atualizada`

---

### Task 5: Scheduler (cron 2 min, lock, FCM, evento), controller do Gmail emite, conexão zera `lastHistoryId`, `status()` com `ultimaSincronizacao`

**Files:**
- Modify: `backend/package.json` (dependência `@nestjs/event-emitter`), `backend/src/app.module.ts`
- Create: `backend/src/gmail/events/gmail-conectado.event.ts`
- Modify: `backend/src/gmail/gmail.controller.ts`, `backend/src/gmail/gmail-connections.service.ts` (+ specs)
- Modify: `backend/src/email-sync/email-sync.scheduler.ts`, `backend/src/email-sync/email-sync.scheduler.spec.ts`

**Interfaces:**
- Consumes: `EmailSyncLockService` (T1), `syncUser → { novos, novosPrecisamAtencao }` (T3), `notifyInboxAtualizada` (T4).
- Produces: `export const GMAIL_CONECTADO = 'gmail.conectado'; export class GmailConectadoEvent { constructor(readonly userId: string) {} }`; `EmailSyncScheduler.aoConectar(evento: GmailConectadoEvent): Promise<void>`; `GmailConnectionsService.status()` devolve também `ultimaSincronizacao: string | null`.

- [ ] **Step 1:** `cd backend && npm i @nestjs/event-emitter@^3` (versão compatível com Nest 11; confirme com `npm ls @nestjs/core`). Em `app.module.ts`: `EventEmitterModule.forRoot()` ao lado de `ScheduleModule.forRoot()`.

- [ ] **Step 2: Testes do scheduler** (adaptar `buildScheduler` para injetar `lock` e `notificationService.notifyInboxAtualizada`):

```ts
function build(over: Partial<{ syncUser: jest.Mock }> = {}) {
  const prisma = { gmailConnection: { findMany: jest.fn().mockResolvedValue([{ userId: 'u1' }, { userId: 'u2' }]) } };
  const emailSyncService = { syncUser: over.syncUser ?? jest.fn().mockResolvedValue({ novos: 0, novosPrecisamAtencao: 0 }) };
  const notificationService = { notifyNewEmailsNeedAttention: jest.fn(), notifyInboxAtualizada: jest.fn() };
  const lock = new EmailSyncLockService();
  const scheduler = new EmailSyncScheduler(prisma as any, emailSyncService as any, notificationService as any, lock);
  return { prisma, emailSyncService, notificationService, lock, scheduler };
}

it('cron é a cada 2 minutos', () => {
  const meta = Reflect.getMetadata(SCHEDULE_CRON_OPTIONS, EmailSyncScheduler.prototype.syncAllConnectedUsers) as { cronTime: string };
  expect(meta.cronTime).toBe('*/2 * * * *');
}); // SCHEDULE_CRON_OPTIONS vem de '@nestjs/schedule/dist/schedule.constants'

it('envia inbox_atualizada quando novos > 0 e não quando 0', async () => {
  const syncUser = jest.fn().mockResolvedValueOnce({ novos: 3, novosPrecisamAtencao: 0 }).mockResolvedValueOnce({ novos: 0, novosPrecisamAtencao: 1 });
  const d = build({ syncUser });
  await d.scheduler.syncAllConnectedUsers();
  expect(d.notificationService.notifyInboxAtualizada).toHaveBeenCalledTimes(1);
  expect(d.notificationService.notifyInboxAtualizada).toHaveBeenCalledWith('u1');
  expect(d.notificationService.notifyNewEmailsNeedAttention).toHaveBeenCalledWith('u2', 1);
});

it('um usuário lento não bloqueia o outro em firings sobrepostos', async () => {
  let libera!: () => void;
  const syncUser = jest.fn()
    .mockImplementationOnce(() => new Promise((r) => { libera = () => r({ novos: 0, novosPrecisamAtencao: 0 }); }))
    .mockResolvedValue({ novos: 0, novosPrecisamAtencao: 0 });
  const d = build({ syncUser });
  const primeiro = d.scheduler.syncAllConnectedUsers();     // u1 fica preso; u2 completa
  await new Promise((r) => setImmediate(r));
  await d.scheduler.syncAllConnectedUsers();                // u1 pulado (lock), u2 roda de novo
  expect(syncUser.mock.calls.filter((c) => c[0] === 'u1')).toHaveLength(1);
  expect(syncUser.mock.calls.filter((c) => c[0] === 'u2')).toHaveLength(2);
  libera(); await primeiro;
});

it('aoConectar sincroniza o usuário do evento e envia FCM quando há novos; erro é engolido e logado', async () => {
  const syncUser = jest.fn().mockResolvedValueOnce({ novos: 2, novosPrecisamAtencao: 0 }).mockRejectedValueOnce(new Error('boom'));
  const d = build({ syncUser });
  await d.scheduler.aoConectar(new GmailConectadoEvent('u9'));
  expect(syncUser).toHaveBeenCalledWith('u9');
  expect(d.notificationService.notifyInboxAtualizada).toHaveBeenCalledWith('u9');
  await expect(d.scheduler.aoConectar(new GmailConectadoEvent('u9'))).resolves.toBeUndefined();
});

it('aoConectar não aplica debounce (roda mesmo com sincronização recente)', async () => {
  const d = build();
  await d.scheduler.aoConectar(new GmailConectadoEvent('u1'));
  await d.scheduler.aoConectar(new GmailConectadoEvent('u1'));
  expect(d.emailSyncService.syncUser).toHaveBeenCalledTimes(2);
});
```
Substituir o teste antigo "does not run two syncs concurrently" pelo de lock por usuário acima.

- [ ] **Step 3: Implementar o scheduler**

```ts
@Cron('*/2 * * * *')
async syncAllConnectedUsers(): Promise<void> {
  const connections = await this.prisma.gmailConnection.findMany({ select: { userId: true } });
  for (const { userId } of connections) await this.sincronizarComLock(userId);
}

@OnEvent(GMAIL_CONECTADO)
async aoConectar(evento: GmailConectadoEvent): Promise<void> {
  await this.sincronizarComLock(evento.userId);
}

/** Um usuário por vez (lock), FCM de dados quando houve novos, notificação visível como antes.
 *  Nunca lança — é chamado pelo cron e pelo `emit()` síncrono do controller. */
private async sincronizarComLock(userId: string): Promise<void> {
  try {
    const r = await this.lock.executar(userId, () => this.emailSyncService.syncUser(userId));
    if (!r) { this.logger.debug(`sync já em andamento para ${userId}; pulando`); return; }
    if (r.novos > 0) await this.notificationService.notifyInboxAtualizada(userId);
    if (r.novosPrecisamAtencao > 0) await this.notificationService.notifyNewEmailsNeedAttention(userId, r.novosPrecisamAtencao);
  } catch (error) {
    this.logger.error(`Failed to sync Gmail for user ${userId}`, error as Error);
  }
}
```
Construtor: `(prisma, emailSyncService, notificationService, private readonly lock: EmailSyncLockService)`. Remover `private running`.

- [ ] **Step 4: Controller do Gmail e conexão**

`gmail/events/gmail-conectado.event.ts`:
```ts
export const GMAIL_CONECTADO = 'gmail.conectado';
export class GmailConectadoEvent { constructor(readonly userId: string) {} }
```
`gmail.controller.ts`: injetar `private readonly eventEmitter: EventEmitter2`; em `connect`:
```ts
const conexao = await this.connectionsService.connect(firebaseUid, dto.serverAuthCode);
this.eventEmitter.emit(GMAIL_CONECTADO, new GmailConectadoEvent(conexao.userId)); // emit(), não emitAsync(): a resposta não espera a sincronização
return { success: true };
```
`gmail-connections.service.ts`: no `upsert`, `update: { …, lastHistoryId: null }` (reconectar repovoa a caixa); `status()` acrescenta `ultimaSincronizacao: connection?.ultimaSincronizacao?.toISOString() ?? null`. Testes: `connect()` reconectando → `update` contém `lastHistoryId: null`; `status()` com/sem data. Teste do controller: `emit` chamado com `(GMAIL_CONECTADO, { userId })` após `connect`; resposta `{ success: true }` mesmo com ouvinte que rejeita (mock do emitter).

- [ ] **Step 5:** `npm test -- src/email-sync src/gmail src/app.module` (se existir spec) → PASS; `tsc` limpo. Compilar `AppModule` num `Test.createTestingModule` com `PrismaService`/`FIREBASE_ADMIN` mockados para provar que `EventEmitterModule` resolve (pode ser um `it` em `email-sync.scheduler.spec.ts` ou spec novo `app.module.spec.ts`).
- [ ] **Step 6: Commit** — `feat(email-sync): cron de 2 min com lock por usuário, sync ao conectar via evento e push de dados`

---

### Task 6: `GET /resumos-email` paginado com compat e `POST /resumos-email/sincronizar`

**Files:**
- Modify: `backend/src/email-sync/email-summary.controller.ts`, `backend/src/email-sync/email-summary.controller.spec.ts`

**Interfaces:**
- Consumes: `listarLegado`, `listarPagina` (T3), `EmailSyncLockService` (T1), `syncUser` (T3), `getConnectionOrThrow` (existente), `mapearErroGmail` (existente).
- Produces: `GET /resumos-email` → array (sem parâmetros) | `{ itens, proximoCursor }` (com `cursor` ou `limite`); `POST /resumos-email/sincronizar` → `200 { executado: true, novos, ultimaSincronizacao }` | `202 { executado: false, motivo: 'recente' | 'em_andamento', ultimaSincronizacao? }`.

- [ ] **Step 1: Testes**

```ts
it('GET sem parâmetros usa listarLegado', async () => { /* list(fb) → emailSyncService.listarLegado chamado; resultado é array */ });
it('GET com limite usa listarPagina com default de cursor undefined', async () => { /* list(fb, undefined, '50') → listarPagina(fb, { cursor: undefined, limite: 50 }) */ });
it('GET só com cursor usa limite 50', async () => { /* list(fb, 'abc', undefined) → listarPagina(fb, { cursor: 'abc', limite: 50 }) */ });

describe('POST sincronizar', () => {
  it('403 sem conexão', async () => { connectionsService.getConnectionOrThrow.mockRejectedValue(new ForbiddenException('Gmail não conectado.')); await expect(ctrl.sincronizar('fb')).rejects.toThrow('Gmail não conectado.'); });
  it('202 recente dentro de 30 s, sem chamar syncUser', async () => {
    connectionsService.getConnectionOrThrow.mockResolvedValue({ userId: 'u1', ultimaSincronizacao: new Date(Date.now() - 10_000) });
    const r = await ctrl.sincronizar('fb'); // ctrl usa @Res? não — devolve objeto e @HttpCode dinâmico via @Res({ passthrough: true })
    expect(r).toMatchObject({ executado: false, motivo: 'recente' }); expect(emailSyncService.syncUser).not.toHaveBeenCalled();
  });
  it('202 em_andamento quando o lock está ocupado', async () => { /* lock.executar → null */ });
  it('200 com novos e ultimaSincronizacao relida', async () => {
    connectionsService.getConnectionOrThrow.mockResolvedValue({ userId: 'u1', ultimaSincronizacao: new Date(Date.now() - 120_000) });
    emailSyncService.syncUser.mockResolvedValue({ novos: 2, novosPrecisamAtencao: 0 });
    prisma.gmailConnection.findUnique.mockResolvedValue({ ultimaSincronizacao: new Date('2026-09-16T20:00:00Z') });
    expect(await ctrl.sincronizar('fb')).toEqual({ executado: true, novos: 2, ultimaSincronizacao: '2026-09-16T20:00:00.000Z' });
  });
  it('erro 401 do Gmail vira 403 via mapearErroGmail', async () => { /* syncUser rejeita com { code: 401, config: {} } → rejects ForbiddenException */ });
});
```
Use `@Res({ passthrough: true }) res: Response` para definir `res.status(202)` nos ramos `recente`/`em_andamento` e `200` no sucesso; nos testes passe `{ status: jest.fn().mockReturnThis() }`.

- [ ] **Step 2:** FAIL. **Step 3: Implementar**

```ts
@Get()
async list(@CurrentFirebaseUid() firebaseUid: string, @Query('cursor') cursor?: string, @Query('limite') limite?: string) {
  if (cursor === undefined && limite === undefined) return this.emailSyncService.listarLegado(firebaseUid);
  return this.emailSyncService.listarPagina(firebaseUid, { cursor, limite: limite === undefined ? 50 : Number(limite) });
}

const DEBOUNCE_MS = 30_000;

@Post('sincronizar')
async sincronizar(@CurrentFirebaseUid() firebaseUid: string, @Res({ passthrough: true }) res: Response) {
  const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
  const conn = await this.connectionsService.getConnectionOrThrow(user.id); // 403 'Gmail não conectado.'
  const ultima = conn.ultimaSincronizacao;
  if (ultima && Date.now() - ultima.getTime() < DEBOUNCE_MS) {
    res.status(202);
    return { executado: false, motivo: 'recente', ultimaSincronizacao: ultima.toISOString() };
  }
  let r: { novos: number; novosPrecisamAtencao: number } | null;
  try {
    r = await this.lock.executar(user.id, () => this.emailSyncService.syncUser(user.id));
  } catch (error) {
    throw mapearErroGmail(error);
  }
  if (!r) { res.status(202); return { executado: false, motivo: 'em_andamento' }; }
  const relida = await this.prisma.gmailConnection.findUnique({ where: { userId: user.id } });
  return { executado: true, novos: r.novos, ultimaSincronizacao: relida?.ultimaSincronizacao?.toISOString() ?? null };
}
```
Injetar `EmailSyncLockService` e `PrismaService` no controller (ambos já disponíveis no módulo).

- [ ] **Step 4:** `npm test -- src/email-sync` → PASS; `tsc` limpo; `npm test` completo verde (e2e não roda aqui, mas `tsc` cobre `test/**`).
- [ ] **Step 5: Commit** — `feat(email-sync): listagem paginada por cursor com compat e sincronização sob demanda`

---

### Task 7: Mobile — constante compartilhada, `ultimaSincronizacao`, repositório

**Files:**
- Create: `mobile/lib/core/revalidation.dart`
- Modify: `mobile/lib/features/calendar/calendar_screen.dart` (linhas 14-18 definição+racional, 39 comentário, 68 uso)
- Modify: `mobile/lib/features/email_triage/gmail_connection_repository.dart` (`GmailConnectionStatus`)
- Modify: `mobile/lib/features/email_triage/email_summary_repository.dart`
- Test: `mobile/test/features/email_triage/gmail_connection_repository_test.dart`, `mobile/test/features/email_triage/email_summary_repository_test.dart`

**Interfaces:**
- Produces: `const Duration kRevalidationMinInterval = Duration(seconds: 30);`; `GmailConnectionStatus.ultimaSincronizacao: DateTime?`; `class PaginaResumos { final List<EmailSummary> itens; final String? proximoCursor; }`; `EmailSummaryRepository.listar({String? cursor, int limite = 50}): Future<PaginaResumos>`; `EmailSummaryRepository.sincronizar(): Future<void>` (2xx ok; erros `DioException` propagam). `list()` atual permanece (usado por testes/telas legadas) delegando a `listar()` e devolvendo `itens`.

- [ ] **Step 1: Testes**

```dart
test('fromJson lê ultimaSincronizacao ISO e tolera ausente/null', () {
  final a = GmailConnectionStatus.fromJson({'connected': true, 'ultimaSincronizacao': '2026-09-16T20:00:00.000Z'});
  expect(a.ultimaSincronizacao, DateTime.parse('2026-09-16T20:00:00.000Z'));
  expect(GmailConnectionStatus.fromJson({'connected': true}).ultimaSincronizacao, isNull);
  expect(GmailConnectionStatus.fromJson({'connected': true, 'ultimaSincronizacao': null}).ultimaSincronizacao, isNull);
});

test('listar manda limite e cursor e devolve página', () async {
  Map<String, dynamic>? params;
  final dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
    params = o.queryParameters;
    h.resolve(Response(requestOptions: o, statusCode: 200, data: {'itens': [/* um resumo */], 'proximoCursor': 'abc'}));
  }));
  final p = await EmailSummaryRepository(dio).listar(cursor: 'xyz', limite: 20);
  expect(params, {'limite': '20', 'cursor': 'xyz'});
  expect(p.itens, hasLength(1)); expect(p.proximoCursor, 'abc');
});
test('listar sem cursor não manda o parâmetro', ...);
test('sincronizar faz POST /resumos-email/sincronizar e aceita 202', ...);
test('sincronizar propaga DioException 403', ...);
```

- [ ] **Step 2:** `flutter test test/features/email_triage/` → FAIL.

- [ ] **Step 3: Implementar**

`core/revalidation.dart` (com o racional movido de `calendar_screen.dart:14-17`):
```dart
/// Intervalo mínimo entre revalidações disparadas por `AppLifecycleState.resumed`. 30 s é curto
/// o bastante para o usuário nunca perceber dados desatualizados ao voltar ao app e longo o
/// bastante para não gerar rajada de requisições em quem alterna de app repetidamente.
const Duration kRevalidationMinInterval = Duration(seconds: 30);
```
`calendar_screen.dart`: remover a definição local, importar `../../core/revalidation.dart`, trocar os usos (`:39` comentário, `:68`).

`GmailConnectionStatus`: campo `final DateTime? ultimaSincronizacao;` no construtor (opcional) e em `fromJson`: `ultimaSincronizacao: (json['ultimaSincronizacao'] as String?) != null ? DateTime.parse(json['ultimaSincronizacao'] as String) : null`.

`email_summary_repository.dart`:
```dart
class PaginaResumos {
  const PaginaResumos({required this.itens, this.proximoCursor});
  final List<EmailSummary> itens;
  final String? proximoCursor;
}

Future<PaginaResumos> listar({String? cursor, int limite = 50}) async {
  final response = await _dio.get('/resumos-email', queryParameters: {
    'limite': '$limite',
    if (cursor != null) 'cursor': cursor,
  });
  final data = response.data as Map<String, dynamic>;
  return PaginaResumos(
    itens: (data['itens'] as List<dynamic>).map((j) => EmailSummary.fromJson(j as Map<String, dynamic>)).toList(),
    proximoCursor: data['proximoCursor'] as String?,
  );
}

/// Mantido para compatibilidade dos testes/fakes existentes; devolve só a primeira página.
Future<List<EmailSummary>> list() async => (await listar()).itens;

/// Pede ao backend para sincronizar agora. 2xx (inclusive 202 "recente"/"em_andamento") é
/// sucesso; 403 (Gmail não conectado) e outros erros propagam como [DioException].
Future<void> sincronizar() async {
  await _dio.post('/resumos-email/sincronizar');
}
```
(O teste existente "list parses the array" passa a esperar o formato paginado — atualize-o para `{'itens': [...], 'proximoCursor': null}`.)

- [ ] **Step 4:** `flutter test test/features/email_triage/ test/features/calendar/` → PASS; `flutter analyze lib/core/revalidation.dart lib/features/calendar/calendar_screen.dart lib/features/email_triage/` limpo.
- [ ] **Step 5: Commit** — `feat(mobile): repositório paginado com sincronizar(), ultimaSincronizacao no status e constante de revalidação compartilhada`

---

### Task 8: Mobile — `EmailSummariesNotifier` e `InboxScreen`

**Files:**
- Modify: `mobile/lib/features/email_triage/email_triage_providers.dart` (`emailSummariesProvider` ~42-44)
- Modify: `mobile/lib/features/email_triage/inbox_screen.dart`
- Test: `mobile/test/features/email_triage/inbox_screen_test.dart` (+ novo `email_summaries_notifier_test.dart`)

**Interfaces:**
- Consumes: `PaginaResumos`, `listar`, `sincronizar` (T7), `kRevalidationMinInterval` (T7), `GmailConnectionStatus.ultimaSincronizacao` (T7).
- Produces:
  ```dart
  class PaginaResumosEstado { final List<EmailSummary> itens; final String? proximoCursor; final bool carregandoMais; }
  class EmailSummariesNotifier extends AutoDisposeAsyncNotifier<PaginaResumosEstado> {
    Future<void> recarregar();   // página 1
    Future<void> carregarMais(); // no-op sem cursor ou já carregando
  }
  final emailSummariesProvider = AsyncNotifierProvider.autoDispose<EmailSummariesNotifier, PaginaResumosEstado>(EmailSummariesNotifier.new);
  ```
  (flutter_riverpod 3: `AutoDisposeAsyncNotifier`/`AsyncNotifierProvider.autoDispose` — se a versão 3.3.2 expuser apenas `AsyncNotifier` + `AsyncNotifierProvider.autoDispose`, use essa forma; confirme no pacote em `~/.pub-cache/hosted/pub.dev/flutter_riverpod-3.3.2`.)

- [ ] **Step 1: Testes do notifier** (com `ProviderContainer` e `overrideWith` do repositório fake existente no `inbox_screen_test.dart`, estendendo o fake com `listar`/`sincronizar`):

```dart
test('build carrega a página 1; carregarMais concatena e atualiza o cursor; sem cursor é no-op', () async {
  final repo = _FakeRepo(paginas: [PaginaResumos(itens: [s1, s2], proximoCursor: 'c1'), PaginaResumos(itens: [s3], proximoCursor: null)]);
  final c = ProviderContainer(overrides: [emailSummaryRepositoryProvider.overrideWithValue(repo)]);
  addTearDown(c.dispose);
  final sub = c.listen(emailSummariesProvider, (_, __) {});
  final e1 = await c.read(emailSummariesProvider.future);
  expect(e1.itens.map((s) => s.id), ['s1', 's2']); expect(e1.proximoCursor, 'c1');
  await c.read(emailSummariesProvider.notifier).carregarMais();
  final e2 = c.read(emailSummariesProvider).requireValue;
  expect(e2.itens.map((s) => s.id), ['s1', 's2', 's3']); expect(e2.proximoCursor, isNull);
  await c.read(emailSummariesProvider.notifier).carregarMais();
  expect(repo.chamadasListar, 2);
  sub.close();
});
test('recarregar substitui pela página 1', ...);
```

- [ ] **Step 2: Testes da tela** (estender `inbox_screen_test.dart`):
  - pull-to-refresh chama `sincronizar()` antes de `listar()` (ordem registrada no fake) e ignora 202;
  - `sincronizar()` lançando `DioException` 403 → SnackBar/CTA de reconexão via `_mostrarReconectar` existente (mesma cópia "Reconecte o Gmail…" — escolha: `'Reconecte o Gmail para atualizar a caixa.'`);
  - "Carregar mais" só aparece com `proximoCursor != null` e chama `carregarMais()`;
  - `resumed` chama `recarregar()` no máximo 1× em 30 s (simular `TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged`);
  - estado vazio: `connected && ultimaSincronizacao == null` → texto "Sincronizando sua caixa… isso leva alguns segundos." e `recarregar()` a cada 5 s (usar `fakeAsync`/`tester.pump(Duration(seconds: 5))`), timer cancelado ao dispor; após 60 s ainda vazio → `_EmptyState` "Nenhum e-mail novo por aqui.";
  - `connected && ultimaSincronizacao != null && vazio` → `_EmptyState` direto.

- [ ] **Step 3: Implementar**

Notifier em `email_triage_providers.dart`:
```dart
class PaginaResumosEstado {
  const PaginaResumosEstado({required this.itens, this.proximoCursor, this.carregandoMais = false});
  final List<EmailSummary> itens; final String? proximoCursor; final bool carregandoMais;
  PaginaResumosEstado copyWith({List<EmailSummary>? itens, String? proximoCursor, bool limparCursor = false, bool? carregandoMais}) => PaginaResumosEstado(
    itens: itens ?? this.itens, proximoCursor: limparCursor ? null : (proximoCursor ?? this.proximoCursor), carregandoMais: carregandoMais ?? this.carregandoMais);
}

class EmailSummariesNotifier extends AutoDisposeAsyncNotifier<PaginaResumosEstado> {
  @override
  Future<PaginaResumosEstado> build() async {
    final p = await ref.watch(emailSummaryRepositoryProvider).listar();
    return PaginaResumosEstado(itens: p.itens, proximoCursor: p.proximoCursor);
  }
  Future<void> recarregar() async { ref.invalidateSelf(); await future; }
  Future<void> carregarMais() async {
    final atual = state.valueOrNull;
    if (atual == null || atual.proximoCursor == null || atual.carregandoMais) return;
    state = AsyncData(atual.copyWith(carregandoMais: true));
    try {
      final p = await ref.read(emailSummaryRepositoryProvider).listar(cursor: atual.proximoCursor);
      state = AsyncData(PaginaResumosEstado(itens: [...atual.itens, ...p.itens], proximoCursor: p.proximoCursor));
    } catch (_) {
      state = AsyncData(atual.copyWith(carregandoMais: false));
    }
  }
}
final emailSummariesProvider = AsyncNotifierProvider.autoDispose<EmailSummariesNotifier, PaginaResumosEstado>(EmailSummariesNotifier.new);
```

`InboxScreen` vira `ConsumerStatefulWidget` com `WidgetsBindingObserver` (`_lastRevalidatedAt`, padrão de `calendar_screen.dart:57-73` usando `kRevalidationMinInterval`); `onRefresh`: `try { await repo.sincronizar(); } on DioException catch (e) { if (e.response?.statusCode == 403) _mostrarReconectar('Reconecte o Gmail para atualizar a caixa.'); } finally { await notifier.recarregar(); }`; no fim da lista, se `estado.proximoCursor != null`, um `ListTile`/`TextButton` "Carregar mais" (ou `CircularProgressIndicator` se `carregandoMais`); estado vazio com `Timer.periodic(const Duration(seconds: 5))` limitado a 60 s (`_tentativas < 12`), cancelado em `dispose` e quando `itens` deixa de ser vazio; widget `_SincronizandoState` com o texto "Sincronizando sua caixa… isso leva alguns segundos.".

Todos os `ref.invalidate(emailSummariesProvider)` existentes na tela (arquivar/excluir, `:444`/`:492`) continuam válidos (invalidate refaz `build`).

- [ ] **Step 4:** `flutter test test/features/email_triage/` → PASS; `flutter analyze lib/features/email_triage/` limpo.
- [ ] **Step 5: Commit** — `feat(mobile): caixa de entrada com sincronização ao puxar, paginação, refresh ao retomar e estado de sincronização`

---

### Task 9: Mobile — `conectarGmail(ref)`, quatro sítios, `main.dart` (`ProviderContainer` + `onMessage`)

**Files:**
- Modify: `mobile/lib/features/email_triage/gmail_connection_actions.dart`, `mobile/lib/features/home/home_screen.dart` (`_conectarGmail` ~875-891), `mobile/lib/features/calendar/calendar_screen.dart` (`_reconectarGmail` ~360-374), `mobile/lib/features/email_triage/email_detail_screen.dart` (`_reconectar` ~162-173), `mobile/lib/main.dart`
- Test: `mobile/test/features/email_triage/gmail_connection_actions_test.dart` (novo), ajustes em `inbox_screen_test.dart`/`home` tests se existirem

**Interfaces:**
- Produces: `Future<void> conectarGmail(WidgetRef ref)` em `gmail_connection_actions.dart`; `final providerContainer = ProviderContainer();` em `main.dart`.

- [ ] **Step 1: Testes**
  - `conectarGmail`: chama `connect()`; invalida `gmailConnectionStatusProvider` e `emailSummariesProvider` (observar recomputação via `ProviderContainer`/widget de teste); relança erro do `connect()` sem invalidar; widget removido da árvore durante o `connect()` (fake com `Completer`, `pumpWidget(SizedBox())` antes de completar) → nenhum `invalidate`, nada lança.
  - `reconectarGmailEAvisar`: nos dois ramos a lista é recarregada (fake `listar` chamado após a reconexão); só `avisarSucesso == true` mostra SnackBar.
  - Widget test da Home: botão "Conectar Gmail" chama `connect()` uma vez; erro mostra "Não foi possível conectar o Gmail. Tente novamente.".
  - Calendário: após reconectar, `upcomingEventsProvider`/`monthEventsProvider` são invalidados (fake dos repositórios com contador).

- [ ] **Step 2: Implementar**

`gmail_connection_actions.dart`:
```dart
/// Conecta o Gmail e invalida o que TODA conexão precisa recarregar. Relança qualquer erro:
/// cada sítio mantém o próprio try/catch + SnackBar (as cópias atuais não mudam).
/// O `await` cobre o consentimento do Google (longo); se o widget saiu da árvore nesse meio-tempo,
/// não toca em `ref` — em flutter_riverpod 3 `WidgetRef.invalidate` chama `_assertNotDisposed()`.
Future<void> conectarGmail(WidgetRef ref) async {
  await ref.read(gmailConnectionRepositoryProvider).connect();
  if (!ref.context.mounted) return;
  ref.invalidate(gmailConnectionStatusProvider);
  ref.invalidate(emailSummariesProvider);
}
```
- `reconectarGmail`: `await conectarGmail(ref); return await ref.refresh(gmailConnectionStatusProvider.future);` (try/catch + SnackBar como hoje).
- `reconectarGmailEAvisar`: remover o `ref.invalidate(emailSummariesProvider)` do ramo `!avisarSucesso` (o helper já faz) e atualizar o doc-comment ("reconectar zera o cursor no backend e repovoa a caixa; a lista é recarregada nos dois casos").
- `home_screen.dart` `_conectarGmail`: `await conectarGmail(ref);` no lugar de `connect()` + `invalidate(status)`; catch inalterado.
- `calendar_screen.dart` `_reconectarGmail`: `await conectarGmail(ref); ref.invalidate(upcomingEventsProvider); ref.invalidate(monthEventsProvider);` (mantém o comentário `:357-359` e o catch).
- `email_detail_screen.dart` `_reconectar`: `await conectarGmail(ref);` (a guarda vive no helper); catch com `if (!mounted) return;` inalterado.
- `main.dart`: `final providerContainer = ProviderContainer();` no topo; antes do `runApp`:
  ```dart
  // Push só de dados do backend (`inbox_atualizada`): sem UI, só relê a caixa. Em segundo plano
  // nada é feito aqui — a tela recarrega ao voltar ao primeiro plano (`resumed`).
  FirebaseMessaging.onMessage.listen((m) {
    if (m.data['tipo'] == 'inbox_atualizada') providerContainer.invalidate(emailSummariesProvider);
  });
  runApp(UncontrolledProviderScope(container: providerContainer, child: const SincroApp()));
  ```
  Extrair o handler para `void handleInboxAtualizada(RemoteMessage m, ProviderContainer container)` testável (teste: `tipo == 'inbox_atualizada'` invalida; outro tipo não).

- [ ] **Step 3:** `flutter test` completo → verde (8 falhas pré-existentes em `app_chip*_test.dart` são conhecidas — reporte se persistirem); `flutter analyze lib/` sem erros novos.
- [ ] **Step 4: Commit** — `feat(mobile): helper conectarGmail nos quatro pontos de conexão e refresh da caixa por push de dados`

---

### Task 10: Verificação final

- [ ] `cd backend && npm test` → 100 %; `npx tsc --noEmit -p tsconfig.json` limpo; `npx prisma validate`; `migrate diff` contra shadow DB (container `backend-postgres-1`, como nas tasks anteriores) → único resíduo aceitável o `DROP INDEX` HNSW pré-existente.
- [ ] `Test.createTestingModule({ imports: [PrismaModule, EmailSyncModule, GmailModule] })` compila com `PrismaService`/`FIREBASE_ADMIN` mockados; emitir `gmail.conectado` no `EventEmitter2` do módulo e observar `syncUser` mockado ser chamado (prova a ligação real controller → scheduler).
- [ ] `cd mobile && flutter test` → verde (exceto falhas pré-existentes documentadas); `flutter analyze`.
- [ ] `grep -rn "fetchInitialUnread\|private running" backend/src` → vazio; `grep -rn "\.list()" mobile/lib/features/email_triage` → só o `list()` de compatibilidade no repositório.
- [ ] Atualizar "Critérios de sucesso" da spec com os números medidos. Commit: `chore(inbox): verificação final da sincronização rápida`.

## Self-Review

**Spec coverage** — Decisões 1–11 ↔ T5 (cron, lock, evento), T2 (Atualizações, INBOX, inicial 30 d/200, history paginado), T6 (manual + debounce + compat GET), T3 (`novos`, cursor, índice), T4 (FCM dados), T9 (`main.dart`, helper, sítios), T7/T8 (status `ultimaSincronizacao`, notifier, tela), T5 (`status()` expõe `ultimaSincronizacao`, reconectar zera `lastHistoryId`). Fora de escopo mantido fora.

**Placeholders** — nenhum TBD; os `/* … */` nos testes descrevem asserções concretas a escrever com o padrão do arquivo (fábricas já existentes).

**Type consistency** — `syncUser → { novos, novosPrecisamAtencao }` (T3) consumido em T5/T6; `listarLegado/listarPagina` (T3) em T6; `EmailSyncLockService.executar` (T1) em T5/T6; `GmailConectadoEvent`/`GMAIL_CONECTADO` (T5) no controller e scheduler; `PaginaResumos`/`listar`/`sincronizar` (T7) em T8; `kRevalidationMinInterval` (T7) em T8; `conectarGmail` (T9) nos sítios; `emailSummariesProvider` como `AsyncNotifierProvider.autoDispose` (T8) invalidado em T9.
