# Caixa de Entrada — sincronização rápida com o Gmail (opção B + itens comuns)

## Contexto e objetivo

Hoje uma mensagem nova no Gmail só aparece no app quando **três** coisas acontecem: o cron de
20 minutos roda (`backend/src/email-sync/email-sync.scheduler.ts:22`), a mensagem sobrevive aos
filtros do `GmailApiClient` (aba Principal apenas; primeira sincronização só não lidas dos
últimos 7 dias, máximo 50) e o usuário reabre a tela ou puxa para atualizar — o app só relê o
banco (`GET /resumos-email`), nunca fala com o Gmail. Resultado observado pelo usuário em
2026-09-16: ao conectar, a caixa fica vazia por até 20 min; mensagens novas em Atualizações
nunca aparecem; mensagens além das 100 mais recentes somem (`list()` corta em 100).

**Objetivo:** uma mensagem que chega no Gmail aparece no app em **até 2 minutos**, sem ação do
usuário; ao conectar, a caixa é preenchida em segundos; a aba Atualizações passa a entrar.

**Opção escolhida (brainstorming 2026-09-16):** B — polling curto + sincronização sob demanda —
mais os quatro itens comuns. A opção A (Gmail Push via Pub/Sub, latência de segundos) fica como
fase seguinte e exige setup no GCP pelo dono do projeto; quando entrar, o polling desta spec vira
rede de segurança.

## Decisões

1. **Cron de `*/20` para `*/2`** (a cada 2 min). `history.list` incremental é barato (2 unidades
   de cota por chamada, limite de 250 unidades/s/usuário e 1 000 000/dia por projeto — números da
   documentação do Gmail API, a confirmar no console antes do deploy). Com N usuários conectados,
   o custo por ciclo é ~N × (2 + 5 × mensagens novas) unidades.
2. **Lock por usuário, não global.** O guard `running` do scheduler vira um `Set<userId>` em
   memória: um usuário lento (reprocessamento de finanças, PDF) não segura os outros, e o mesmo
   usuário nunca roda em paralelo (cron × endpoint manual × conexão). Premissa mantida: uma réplica
   do backend.
3. **Sincronizar ao conectar.** `GmailController.connect` emite `gmail.conectado` (`emit()`,
   síncrono e sem aguardar) depois que `connectionsService.connect()` retorna; o
   `EmailSyncScheduler` escuta e roda `syncUser` dentro do lock por usuário, com `try/catch` +
   `logger.error`. A resposta HTTP do `connect` não espera a sincronização.
4. **Sincronização sob demanda.** `POST /resumos-email/sincronizar` executa `syncUser` para o
   usuário autenticado, com **debounce de 30 s** sobre `GmailConnection.ultimaSincronizacao` (já
   existe; só o endpoint manual aplica o debounce — o cron nunca). Se a última sincronização foi há
   menos de 30 s → `202 { executado: false, motivo: 'recente', ultimaSincronizacao }` sem chamar o
   Gmail. Como o cron de 2 min também grava `ultimaSincronizacao`, é aceitável (e esperado) que o
   "puxar para atualizar" receba `202` em parte dos casos: o app relê a lista de qualquer forma e não
   mostra erro. `hasUnrecoverableFailure` mantém `ultimaSincronizacao` antiga (comportamento atual,
   `email-sync.service.ts:183-190`) — nesse caso o manual passa a ser permitido, o que é desejado.
5. **Aba Atualizações entra; Promoções, Social e Fóruns continuam fora.** `CATEGORY_UPDATES` sai
   de `NOISE_LABELS` e de `-category:updates` na query inicial. Preferência por usuário fica para
   depois.
6. **Primeira sincronização mais ampla:** `in:inbox` (lidas e não lidas), últimos **30 dias**,
   até **200 mensagens**, paginando `messages.list` (`maxResults: 100`, `nextPageToken`). Também é o
   que roda quando o `historyId` expira. Ordem de processamento: mais recentes primeiro.
7. **O app se atualiza sozinho.** Quando uma sincronização **agendada** (cron ou evento de
   conexão) cria pelo menos um `EmailSummary`, o chamador envia uma **mensagem FCM só de dados** (`data: { tipo: 'inbox_atualizada' }`, sem
   `notification`; Android `priority: 'high'`; iOS `apns.payload.aps.contentAvailable: true` +
   header `apns-push-type: background`) — não aparece na bandeja, não depende da tolerância de
   notificação da anamnese. O app, ao recebê-la em primeiro plano (`FirebaseMessaging.onMessage`) e
   ao voltar ao primeiro plano (`AppLifecycleState.resumed`, com intervalo mínimo de 30 s como em
   `calendar_screen.dart:18,64-70`), invalida `emailSummariesProvider`. A notificação visível
   "N e-mails precisam da sua atenção" continua exatamente como está. O endpoint manual **não**
   envia FCM: o próprio app relê a lista em seguida.
8. **Paginação em vez do corte de 100.** `GET /resumos-email?cursor=<opaco>&limite=50` com
   cursor por `(recebidoEm, id)`; o app carrega 50 e mostra "Carregar mais" ao chegar ao fim.
   **Compatibilidade:** sem `cursor` nem `limite` na query, a rota devolve o **array** dos 100 mais
   recentes exatamente como hoje (app 1.0.12 (5) em campo e os e2e existentes continuam válidos);
   com qualquer um dos dois parâmetros, devolve `{ itens, proximoCursor }`. A tradução é do
   controller; o serviço ganha dois métodos.
9. **Caminho incremental exige `INBOX`.** Com `CATEGORY_UPDATES` liberada, `fetchMessages` passa a
   descartar também mensagens **sem** `INBOX` em `labelIds` (enviadas, arquivadas por filtro,
   rascunhos) — hoje elas entram silenciosamente; com o push de dados, cada uma dispararia um
   `inbox_atualizada` indevido.
10. **`history.list` paginado.** `fetchIncremental` segue `nextPageToken` até esgotar e só então
    devolve o `historyId` mais recente — hoje lê uma página e avança o cursor, perdendo o que
    ficou nas seguintes.
11. **`GET gmail/connection` passa a expor `ultimaSincronizacao`** (ISO ou `null`) — sai de "Fora
    de escopo" porque é o sinal que o app usa para o estado "Sincronizando sua caixa…".

## Fora de escopo

- Gmail Push (`users.watch` + Pub/Sub) — fase seguinte.
- Preferência por usuário de quais abas entram.
- Texto "última sincronização há X" na UI (o campo passa a ser exposto — decisão 11 — mas só é
  usado para o estado vazio nesta fase).
- Reprocessar mensagens que foram descartadas no passado por estarem em Atualizações (não há
  registro delas; só entram as que chegarem daqui em diante ou as dos últimos 30 dias na próxima
  sincronização inicial de quem reconectar).

## Arquitetura

```
Gmail ──(a cada 2 min: cron)──────────────┐
Gmail ──(ao conectar: evento gmail.conectado)─┤
Gmail ──(sob demanda: POST /resumos-email/sincronizar, debounce 30 s)──┤
                                          ▼
                         EmailSyncService.syncUser(userId)   [lock por usuário]
                                          │  cria EmailSummary (+ finanças, já existente)
                                          │  devolve { novos, novosPrecisamAtencao }
              chamadores AGENDADOS (cron / evento gmail.conectado), com o retorno:
                                          ├─ novos > 0 → FCM dados {tipo:'inbox_atualizada'}
                                          └─ novosPrecisamAtencao > 0 → FCM visível (inalterado)
              chamador MANUAL (POST /resumos-email/sincronizar): sem FCM — o app relê a lista
App ── onMessage(inbox_atualizada) | resumed | pull-to-refresh ──► GET /resumos-email?cursor=…
```

## Mudanças por componente

### Backend

**`app.module.ts`** — `EventEmitterModule.forRoot()` (novo pacote `@nestjs/event-emitter`; não está
em `backend/package.json` hoje) ao lado de `ScheduleModule.forRoot()` (`app.module.ts:22`).

**`email-sync-lock.service.ts` (novo, em `src/email-sync/`, provido e exportado por `EmailSyncModule`)**
```ts
@Injectable()
export class EmailSyncLockService {
  private readonly emExecucao = new Set<string>();
  /** Executa `fn` se o usuário não estiver em sincronização; devolve null se pulou. */
  async executar<T>(userId: string, fn: () => Promise<T>): Promise<T | null> {
    if (this.emExecucao.has(userId)) return null;
    this.emExecucao.add(userId);
    try { return await fn(); } finally { this.emExecucao.delete(userId); }
  }
}
```

**`email-sync.scheduler.ts`**
- `@Cron('*/2 * * * *')`; remove `private running`; injeta `EmailSyncLockService`.
- Loop: `const r = await lock.executar(userId, () => syncUser(userId)); if (!r) { debug('sync já em
  andamento, pulando'); continue; }`; depois `if (r.novos > 0) notifyInboxAtualizada(userId)`;
  `if (r.novosPrecisamAtencao > 0) notifyNewEmailsNeedAttention(...)` (inalterado).
- `@OnEvent('gmail.conectado')` `async aoConectar({ userId }: GmailConectadoEvent)`: mesmo corpo do
  loop para um único usuário, inteiro dentro de `try/catch` com `logger.error` — é chamado pelo
  `emit()` síncrono do controller, então a Promise **precisa** ser tratada aqui para não virar
  unhandled rejection.

**`email-sync.service.ts`**
- `syncUser` devolve `{ novos: number; novosPrecisamAtencao: number }` (`novos` = `create` de
  `emailSummary` bem-sucedidos neste ciclo; duplicados P2002 e falhas não contam).
- `fetchNewEmails`: sem `lastHistoryId` ou `historyExpired` → `gmailApiClient.fetchInitial(refreshToken)`.
- **Dois métodos de listagem** (o `select` explícito atual de `list()` — `email-sync.service.ts:330+`
  — é mantido nos dois; a regra de nunca vazar campos internos continua):
  - `listarLegado(firebaseUid)`: exatamente o `list()` de hoje (array, `take: 100`).
  - `listarPagina(firebaseUid, { cursor?: string; limite: number })`: `limite` limitado a `[1, 100]`;
    cursor decodificado de base64url `${recebidoEm.toISOString()}|${id}`; cursor indecodificável →
    `BadRequestException('Cursor inválido.')`; `where` com `OR: [{ recebidoEm: { lt } }, { recebidoEm,
    id: { lt: id } }]`; `orderBy: [{ recebidoEm: 'desc' }, { id: 'desc' }]`; `take: limite + 1`;
    resposta `{ itens: primeiros limite, proximoCursor: cursor do último item devolvido ou null }`.
    `id` é uuid texto: a comparação `<` do Postgres é a mesma usada pelo `orderBy id desc`, sem
    linhas puladas ou repetidas quando `recebidoEm` empata.
- **Prisma:** `EmailSummary` ganha `@@index([userId, recebidoEm(sort: Desc), id(sort: Desc)])`;
  migration `add_email_summary_cursor_index`.

**`email-summary.controller.ts`**
- `GET /resumos-email`: `if (cursor === undefined && limite === undefined) return listarLegado(...)`;
  senão `listarPagina(...)` (`limite` default 50 quando só `cursor` vem). Os e2e existentes
  (`email-triage-flow`, `email-reply-flow`) não mandam parâmetros → seguem no caminho legado, sem
  alteração.
- `POST /resumos-email/sincronizar`: `const conn = await connectionsService.getConnectionOrThrow(user.id)`
  (403 `'Gmail não conectado.'`, padrão já tratado pelo app como "reconectar"); debounce de 30 s
  sobre `conn.ultimaSincronizacao` → `202 { executado: false, motivo: 'recente', ultimaSincronizacao }`;
  `lock.executar` pulou → `202 { executado: false, motivo: 'em_andamento' }`; sucesso → **relê** a conexão
  (`findUnique`) e responde `200 { executado: true, novos, ultimaSincronizacao }` com o carimbo novo
  (o `conn` lido antes do `syncUser` serve só ao debounce); erro do Gmail → `mapearErroGmail`
  (existente). Sem FCM aqui — o app relê a lista em seguida.

**`gmail.controller.ts` → `connect()`**
- Dependência de módulos hoje: `EmailSyncModule` importa `GmailModule` (`email-sync.module.ts:16`);
  `GmailModule` importa só `AuthModule`, `UsersModule`, `CryptoModule` (`gmail.module.ts:11`) — chamar
  `syncUser` de dentro do `GmailModule` criaria ciclo. Por isso o controller apenas emite:
  `await this.connectionsService.connect(firebaseUid, dto.serverAuthCode); this.eventEmitter.emit('gmail.conectado',
  new GmailConectadoEvent(user.id));` (`EventEmitter2` injetado; `emit()`, não `emitAsync()`). O
  `userId` vem do retorno do `connect()`, que já devolve a `GmailConnection` com `userId`.
- `GmailConectadoEvent { constructor(readonly userId: string) {} }` em `src/gmail/events/`.

**`gmail-connections.service.ts`**
- `connect()`: na branch `update` do `upsert` (`:32-34`) acrescentar `lastHistoryId: null` — hoje o
  cursor antigo é mantido e a caixa não é repovoada ao reconectar. `ultimaSincronizacao` não é
  alterada.
- `status()`: acrescenta `ultimaSincronizacao: connection?.ultimaSincronizacao?.toISOString() ?? null`.

**`gmail-api-client.service.ts`**
- `NOISE_LABELS` = `CATEGORY_PROMOTIONS`, `CATEGORY_SOCIAL`, `CATEGORY_FORUMS`, `SPAM`.
- `fetchMessages`: além do descarte por `NOISE_LABELS`, descarta quando `!labelIds.includes('INBOX')`
  (decisão 9). Vale para os dois caminhos.
- `fetchInitial(refreshToken)` substitui `fetchInitialUnread`: `q = 'in:inbox after:<30 dias>
  -category:promotions -category:social -category:forums'`, `maxResults: 100`, segue `nextPageToken`
  até acumular 200 ids ou acabar; `fetchMessages` como hoje; `historyId` do `getProfile`.
- `fetchIncremental`: laço sobre `nextPageToken` de `history.list` acumulando `messagesAdded`;
  `historyId` devolvido = o da **última** página. 404 → `historyExpired` como hoje.

**`notification.service.ts`**
- `notifyInboxAtualizada(userId)`: se `user.fcmToken`, `messaging().send({ token, data: { tipo:
  'inbox_atualizada' }, android: { priority: 'high' }, apns: { headers: { 'apns-push-type': 'background',
  'apns-priority': '5' }, payload: { aps: { contentAvailable: true } } } })`. Sem `notification`, sem
  checar tolerância (não é interrupção sensorial). Qualquer falha → `warn`, nunca propaga.

### Mobile

**`main.dart`**
- Hoje: `runApp(const ProviderScope(child: SincroApp()))` (`:151`) e handlers FCM como funções de
  topo usando `navigatorKey`. Passa a: `final providerContainer = ProviderContainer();` (topo do
  arquivo) e `runApp(UncontrolledProviderScope(container: providerContainer, child: const SincroApp()))`.
- Novo listener: `FirebaseMessaging.onMessage.listen((m) { if (m.data['tipo'] == 'inbox_atualizada')
  providerContainer.invalidate(emailSummariesProvider); });` — `invalidate` num provider `autoDispose`
  sem ouvintes é inofensivo; quando a caixa montar de novo, ela refaz a busca. Nenhum handler em
  `onBackgroundMessage` (a tela recarrega no `resumed`).
- `onMessageOpenedApp`/`getInitialMessage` continuam como estão (só `tipo: 'email_triage'`).

**`email_summary_repository.dart`** — `listar({ String? cursor, int limite = 50 })` → `PaginaResumos
{ itens, proximoCursor }` chamando `GET /resumos-email?limite=…&cursor=…`; `sincronizar()` →
`POST /resumos-email/sincronizar` (qualquer 2xx é sucesso). Um `403` propaga como `DioException`
e a **tela** checa `e.response?.statusCode == 403` inline — o mesmo padrão já usado na própria
`inbox_screen.dart` para `arquivar`/`excluir` (`inbox_screen.dart:450` e `:498`); não há classe de
exceção nova.

**`gmail_connection_repository.dart`** — `GmailConnectionStatus` ganha `final DateTime?
ultimaSincronizacao`; `fromJson` lê `json['ultimaSincronizacao']` (`String?` ISO → `DateTime.parse`,
`null` quando ausente ou nulo — compatível com backend antigo).

**`email_triage_providers.dart`** — `emailSummariesProvider` vira
`AsyncNotifierProvider.autoDispose<EmailSummariesNotifier, PaginaResumosEstado>` com estado
`{ itens, proximoCursor, carregandoMais }` e métodos `recarregar()` (página 1) e `carregarMais()`
(no-op sem cursor). O `build()` carrega a página 1 — por isso `invalidate` basta para o refresh.

**`inbox_screen.dart`**
- `onRefresh`: `await repo.sincronizar()` (ignora `202`; 403 mostra o CTA de reconexão já existente)
  → `recarregar()`.
- Fim da lista com `proximoCursor != null` → linha "Carregar mais" → `carregarMais()`.
- `WidgetsBindingObserver`: `resumed` → `recarregar()` com intervalo mínimo de 30 s. A constante
  `_kRevalidationMinInterval` de `calendar_screen.dart:18` é privada do arquivo: **extrair** para
  `mobile/lib/core/revalidation.dart` como `kRevalidationMinInterval`, levando junto o racional das
  linhas `:14-17`; em `calendar_screen.dart` a definição sai, o comentário de doc de `:39` passa a
  citar o nome novo e o uso em `:68` importa de `core/revalidation.dart` (refactor sem mudança de
  comportamento).
- **Estado vazio:** se `gmailConnectionStatusProvider` diz `connected && ultimaSincronizacao == null`
  → "Sincronizando sua caixa… isso leva alguns segundos." e a tela chama `recarregar()` a cada 5 s
  por até 60 s (`Timer.periodic`, cancelado no dispose, quando a lista deixa de ser vazia ou aos
  60 s). Esgotados os 60 s ainda vazio → volta ao `_EmptyState` **existente** ("Nenhum e-mail novo por
  aqui.", `inbox_screen.dart:238-259`, cópia inalterada) — sem erro, porque `ultimaSincronizacao`
  continua sendo escrita pelo cron.
  Sem conexão → CTA "Conectar Gmail" como hoje. Na **reconexão** (linha já existente em
  `conexoes_gmail`, `ultimaSincronizacao` preenchida) o indicador não aparece e a lista antiga fica
  visível enquanto o repovoamento acontece — aceitável: o caso comum de "conectar" passa por
  `disconnect`, que apaga a linha.

**Chamadas a `connect()` no app** — são **quatro**: `home_screen.dart:877` (`_conectarGmail`,
primeira conexão pela Home), `calendar_screen.dart:362` (`_reconectarGmail`),
`email_detail_screen.dart:164` (`_reconectar`, método de `State`) e `gmail_connection_actions.dart:83`
(dentro de `reconectarGmail`, usado pelo menu da AppBar da caixa e pelo SnackBar de 403).

Helper novo em `gmail_connection_actions.dart`:
```dart
/// Conecta o Gmail e invalida o que TODA conexão precisa recarregar. Relança qualquer erro:
/// cada sítio mantém o próprio try/catch + SnackBar (as cópias atuais não mudam).
/// O `await` cobre o consentimento do Google (longo); se o widget saiu da árvore nesse meio-tempo,
/// não toca em `ref` — em flutter_riverpod 3 `WidgetRef.invalidate` chama `_assertNotDisposed()`
/// e lançaria.
Future<void> conectarGmail(WidgetRef ref) async {
  await ref.read(gmailConnectionRepositoryProvider).connect();
  if (!ref.context.mounted) return;
  ref.invalidate(gmailConnectionStatusProvider);
  ref.invalidate(emailSummariesProvider);
}
```
Regras por sítio (o que cada um faz **além** do comum é preservado):
- `home_screen.dart` `_conectarGmail`: troca o `connect()` pelo helper; mantém o `try/catch` com
  "Não foi possível conectar o Gmail. Tente novamente." (`:879-891`).
- `calendar_screen.dart` `_reconectarGmail`: troca o `connect()` pelo helper e **mantém** os dois
  `ref.invalidate(upcomingEventsProvider)` / `ref.invalidate(monthEventsProvider)` logo depois
  (comportamento justificado em `:357-359` — a tela precisa sair do estado de erro); mantém o
  `try/catch` com "Não foi possível reconectar. Tente novamente." (`:366-373`).
- `email_detail_screen.dart` `_reconectar` (`:162-173`): hoje o `if (!mounted) return;` (`:165`)
  fica entre o `await connect()` e o `ref.invalidate(gmailConnectionStatusProvider)` — é o
  `invalidate` que ele protege. Com o helper, essa guarda passa a viver **dentro** do helper
  (`ref.context.mounted`, acima), então o sítio vira `await conectarGmail(ref);` seguido de
  `if (!mounted) return;` apenas se houver uso posterior de `context`; mantém o `try/catch` com a
  mesma cópia de reconexão (`:168-172`). Home e calendário hoje não têm guarda nenhuma após o
  `await` — o helper passa a protegê-los também.
- `reconectarGmail`: chama o helper e mantém o `ref.refresh(gmailConnectionStatusProvider.future)`
  para devolver o status relido; o `try/catch` + SnackBar continuam como estão.
- `reconectarGmailEAvisar`: como reconectar agora zera `lastHistoryId` no backend (repovoamento
  completo), a lista **sempre** é recarregada (já feito pelo helper) — o `ref.invalidate` explícito do
  ramo `!avisarSucesso` sai, e o comentário "o conteúdo da caixa de entrada não muda" é atualizado.
  O SnackBar do ramo `avisarSucesso == true` (escopo `gmail.modify` concedido ou não) continua igual.
- **Mudança de comportamento declarada:** calendário e detalhe passam a invalidar
  `emailSummariesProvider`, o que hoje não fazem — inofensivo (`autoDispose`: sem ouvinte, nada é
  buscado) e desejável, porque a reconexão repovoa a caixa.

## Estratégia de testes

**Backend (Jest)**
- `EmailSyncLockService`: executa; devolve `null` quando já em execução para o mesmo usuário; libera
  após erro; usuários diferentes correm em paralelo.
- Scheduler: `@Cron('*/2 * * * *')`; dois usuários, o primeiro lento → o segundo completa; usuário
  pulado loga `debug`; `notifyInboxAtualizada` chamado quando `novos > 0` e não quando `0`;
  `@OnEvent('gmail.conectado')` dispara `syncUser` do usuário e engole/loga erro; o cron **não**
  aplica debounce de 30 s (roda mesmo com `ultimaSincronizacao` recente).
- `GmailController.connect`: `emit('gmail.conectado', { userId })` chamado com `emit`, e a resposta
  HTTP resolve antes de qualquer `syncUser` (mock do emitter sem ouvinte).
- `syncUser` devolve `novos` correto (só `create` OK; P2002 e falhas não contam).
- `fetchInitial`: query sem `is:unread` e sem `-category:updates`, `after` de 30 dias,
  `maxResults: 100`; segue `nextPageToken` e para em 200 ids.
- `fetchMessages`: `CATEGORY_UPDATES` passa; `CATEGORY_PROMOTIONS` é descartada; sem `INBOX`
  (`['SENT']`, `['CATEGORY_UPDATES']` sozinho) é descartada — nos **dois** caminhos
  (`fetchInitial` e `fetchIncremental`).
- `fetchIncremental`: duas páginas de `history.list` → ids de ambas; `historyId` da última página.
- `connect()` na branch `update` zera `lastHistoryId`; `status()` devolve `ultimaSincronizacao` ISO ou `null`.
- Controller `sincronizar`: 403 `'Gmail não conectado.'` sem conexão; 202 `recente` dentro de 30 s;
  202 `em_andamento` com lock ocupado; 200 com `novos`; 401 do Gmail → 403 via `mapearErroGmail`.
- `listarLegado`: array de até 100 (compat). `listarPagina`: `limite=2` devolve 2 e cursor; segunda
  página não repete nem pula item com `recebidoEm` igual; `limite > 100` vira 100; só `cursor` sem
  `limite` usa 50; cursor malformado → 400 `'Cursor inválido.'`; `select` igual ao legado.
- Controller `GET`: sem parâmetros → array; com `limite` ou `cursor` → `{ itens, proximoCursor }`.
- `notifyInboxAtualizada`: payload só `data` + `android.priority` + `apns.aps.contentAvailable` +
  header `apns-push-type: background`; sem `notification`; token inválido não propaga.
- `AppModule` registra `EventEmitterModule.forRoot()` (teste de compilação do módulo com `Test.createTestingModule`).
- Migration: índice `(user_id, recebido_em desc, id desc)` presente (`npx prisma validate` — o CLI
  `prisma` já é usado pelo projeto: `npx prisma generate`/`migrate deploy` no Dockerfile).

**Mobile (flutter test)**
- `EmailSummariesNotifier`: `build` carrega página 1; `recarregar` substitui; `carregarMais`
  concatena e atualiza cursor; sem cursor é no-op.
- `InboxScreen`: "Carregar mais" só com cursor; `resumed` chama `recarregar` no máximo 1× por 30 s;
  pull-to-refresh chama `sincronizar` antes de `recarregar`; 403 no `sincronizar` mostra CTA de
  reconexão; estado vazio "Sincronizando sua caixa…" quando `connected && ultimaSincronizacao == null`,
  com o `Timer` cancelado no dispose.
- `main.dart`: `providerContainer.invalidate(emailSummariesProvider)` para `data.tipo ==
  'inbox_atualizada'`; outros tipos ignorados.
- `conectarGmail(ref)`: invalida os dois providers e **relança** erro do `connect()`; os quatro
  pontos de chamada usam o helper (teste de widget para a Home; para `reconectarGmailEAvisar` nos
  dois ramos — ambos recarregam a lista, só `avisarSucesso == true` mostra SnackBar; para o
  calendário — `upcomingEventsProvider`/`monthEventsProvider` continuam invalidados após reconectar;
  para o detalhe — erro no `connect()` mostra "Não foi possível reconectar. Tente novamente.";
  e um teste do helper em que o widget é removido da árvore durante o `connect()` → nenhum
  `invalidate` é chamado e nada lança).
- `GmailConnectionStatus.fromJson`: `ultimaSincronizacao` ISO → `DateTime`; ausente/`null` → `null`.
- Estado vazio: aos 60 s sem itens, volta ao `_EmptyState` atual ("Nenhum e-mail novo por aqui.") e
  o `Timer` está cancelado.
- `kRevalidationMinInterval` compartilhado: `calendar_screen` e `inbox_screen` importam de `core/revalidation.dart`.

**Manual pós-deploy**
- Conectar o Gmail → "Sincronizando sua caixa…" → lista preenchida em < 30 s.
- Enviar um e-mail para si mesmo → aparece no app em < 2 min sem tocar na tela (primeiro plano) e
  imediatamente ao voltar do segundo plano (Android e iOS).
- E-mail classificado em Atualizações aparece; um de Promoções não; um arquivado por filtro não.
- Console do Google Cloud: cota diária do Gmail após 24 h com o cron de 2 min.

## Critérios de sucesso

- Latência Gmail → app ≤ 2 min em primeiro plano; ≤ 2 min + reabrir em segundo plano.
- Caixa preenchida ao conectar sem esperar o cron.
- Nenhum usuário bloqueia a sincronização de outro; o mesmo usuário nunca sincroniza em paralelo.
- Aba Atualizações visível; Promoções/Social/Fóruns continuam fora.
- `GET /resumos-email` sem parâmetros continua compatível com o app 1.0.12 (5) e com os e2e existentes.
- Suíte backend e mobile verdes; cota do Gmail dentro do limite diário para o número atual de
  usuários (medir no console após 24 h).
