# Biofeedback → Alívio Sensorial: Sugestão de Card no Alerta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the Biofeedback pilar detects a transition to "Elevado", the local alert
notification suggests a specific grounding card by name and tapping it opens that card's detail
screen directly, instead of the generic text/`/biofeedback` destination used today.

**Architecture:** A new pure function (`escolherCardSugerido`) picks a card id from three
already-fetched lists (favoritos → categoria Respiração → qualquer card ativo), called from
`BiofeedbackSyncService._notificarSeNecessario` right before the existing alert fires.
`BiofeedbackAlertService.mostrarAlerta` gains an optional `cardSugerido` parameter that changes
the notification body and encodes the card id in the payload. A new small connector screen
(`GroundingCardSugeridoScreen`) resolves that id against the already-existing grounding-cards
providers and either shows the card's detail screen or falls back to `/biofeedback`.

**Tech Stack:** Flutter (mobile), Riverpod, `flutter_local_notifications`, `mocktail` for tests.
No backend changes.

## Global Constraints

- No FC/VFC/passos/treino/estado de estresse data leaves the device at any point in this feature —
  it consumes only the already-public grounding-cards endpoints and the already-read
  `toleranciaNotificacao` preference.
- No backend changes, no new endpoint. Reuses `GET /grounding-cards`, `GET
  /grounding-cards?categoria=`, `GET /grounding-cards/favoritos` exactly as they exist today.
- The notification title stays fixed: `"Um momento para respirar"`. Only the body changes, and
  only when a card was successfully chosen.
- Any lookup failure (network, empty directory) must never prevent the alert itself from firing —
  it just fires without a suggested card, same as today.
- Grounding-cards screens in this codebase get no `pumpWidget` tests (established convention from
  the Conexão Profissional / Alívio Sensorial specs — UI covered by manual verification). Pure
  logic extracted into standalone functions is what gets unit tests instead.
- `main.dart`'s notification tap handlers depend on globals (`navigatorKey`, `FirebaseAuth`) and
  are not unit-tested today (established in the Fase 3 Biofeedback spec) — this plan does not
  change that; only the pure payload-parsing piece is unit-testable.
- Mocktail conventions already used in this codebase: `class MockX extends Mock implements X {}`
  for dependencies passed to `when()`/`verify()`; `class FakeX extends Fake implements X {}` +
  `registerFallbackValue(FakeX())` in `setUpAll` for any custom type used with `any()`/
  `captureAny()`.

---

## File Structure

| File | Change |
|---|---|
| `mobile/lib/features/biofeedback/escolher_card_sugerido.dart` | **Create.** Pure card-selection function + default random-index helper. |
| `mobile/test/features/biofeedback/escolher_card_sugerido_test.dart` | **Create.** |
| `mobile/lib/features/biofeedback/biofeedback_alert_service.dart` | **Modify.** `mostrarAlerta` gains `cardSugerido`; new `construirConteudoAlerta` and `extrairCardIdDoPayload`. |
| `mobile/test/features/biofeedback/biofeedback_alert_service_test.dart` | **Create.** |
| `mobile/lib/features/grounding_cards/resolver_card_sugerido.dart` | **Create.** Pure id→card lookup. |
| `mobile/test/features/grounding_cards/resolver_card_sugerido_test.dart` | **Create.** |
| `mobile/lib/features/biofeedback/biofeedback_sync_service.dart` | **Modify.** New `GroundingCardsRepository` dependency, `_buscarCardSugerido`. |
| `mobile/test/features/biofeedback/biofeedback_sync_service_test.dart` | **Modify.** `buildService` gains grounding-card stubs; existing `mostrarAlerta()` assertions updated; 2 new tests. |
| `mobile/lib/features/biofeedback/biofeedback_background_task.dart` | **Modify.** Wire `GroundingCardsRepository` into the background isolate's constructor call. |
| `mobile/lib/features/biofeedback/biofeedback_providers.dart` | **Modify.** Wire `GroundingCardsRepository` into the foreground provider's constructor call. |
| `mobile/lib/features/grounding_cards/grounding_card_sugerido_screen.dart` | **Create.** Connector screen: resolves id → detail screen or `/biofeedback`. |
| `mobile/lib/main.dart` | **Modify.** Route registration + tap-handler payload parsing. |

---

### Task 1: `escolherCardSugerido` pure function

**Files:**
- Create: `mobile/lib/features/biofeedback/escolher_card_sugerido.dart`
- Test: `mobile/test/features/biofeedback/escolher_card_sugerido_test.dart`

**Interfaces:**
- Produces: `String? escolherCardSugerido({required List<GroundingCard> favoritos, required List<GroundingCard> respiracaoAtivos, required List<GroundingCard> todosAtivos, required int Function(int max) sortear})` and `int sortearIndiceAleatorio(int max)` — both consumed by Task 4.

- [ ] **Step 1: Write the failing tests**

```dart
// mobile/test/features/biofeedback/escolher_card_sugerido_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/escolher_card_sugerido.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_card.dart';

GroundingCard _card(String id) => GroundingCard(
      id: id,
      titulo: 'Card $id',
      categoria: 'RESPIRACAO',
      conteudo: 'Conteúdo',
      ativo: true,
    );

void main() {
  test('chooses among favoritos when non-empty, ignoring the other two lists', () {
    final resultado = escolherCardSugerido(
      favoritos: [_card('fav-1'), _card('fav-2')],
      respiracaoAtivos: [_card('resp-1')],
      todosAtivos: [_card('todos-1')],
      sortear: (max) => 1,
    );

    expect(resultado, 'fav-2');
  });

  test('falls back to respiracaoAtivos when favoritos is empty', () {
    final resultado = escolherCardSugerido(
      favoritos: [],
      respiracaoAtivos: [_card('resp-1'), _card('resp-2')],
      todosAtivos: [_card('todos-1')],
      sortear: (max) => 0,
    );

    expect(resultado, 'resp-1');
  });

  test('falls back to todosAtivos when favoritos and respiracaoAtivos are both empty', () {
    final resultado = escolherCardSugerido(
      favoritos: [],
      respiracaoAtivos: [],
      todosAtivos: [_card('todos-1'), _card('todos-2')],
      sortear: (max) => 1,
    );

    expect(resultado, 'todos-2');
  });

  test('returns null when all three lists are empty', () {
    final resultado = escolherCardSugerido(
      favoritos: [],
      respiracaoAtivos: [],
      todosAtivos: [],
      sortear: (max) => 0,
    );

    expect(resultado, isNull);
  });

  test('sortear receives the length of the list it is choosing from', () {
    final tamanhosRecebidos = <int>[];
    escolherCardSugerido(
      favoritos: [],
      respiracaoAtivos: [_card('a'), _card('b'), _card('c')],
      todosAtivos: [],
      sortear: (max) {
        tamanhosRecebidos.add(max);
        return 0;
      },
    );

    expect(tamanhosRecebidos, [3]);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mobile && flutter test test/features/biofeedback/escolher_card_sugerido_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:sincro_mobile/features/biofeedback/escolher_card_sugerido.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// mobile/lib/features/biofeedback/escolher_card_sugerido.dart
import 'dart:math';
import '../grounding_cards/grounding_card.dart';

/// Fonte de aleatoriedade padrão para uso em produção — devolve um índice em `[0, max)`, mesmo
/// contrato de `Random.nextInt`. Testes injetam sua própria função em `escolherCardSugerido` para
/// resultados determinísticos.
int sortearIndiceAleatorio(int max) => Random().nextInt(max);

/// Escolhe o id de um grounding card para sugerir junto do alerta de estresse elevado, com
/// prioridade fixa: favoritos do usuário > categoria Respiração > qualquer card ativo. Devolve
/// `null` quando as três listas estão vazias.
String? escolherCardSugerido({
  required List<GroundingCard> favoritos,
  required List<GroundingCard> respiracaoAtivos,
  required List<GroundingCard> todosAtivos,
  required int Function(int max) sortear,
}) {
  if (favoritos.isNotEmpty) return favoritos[sortear(favoritos.length)].id;
  if (respiracaoAtivos.isNotEmpty) return respiracaoAtivos[sortear(respiracaoAtivos.length)].id;
  if (todosAtivos.isNotEmpty) return todosAtivos[sortear(todosAtivos.length)].id;
  return null;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/biofeedback/escolher_card_sugerido_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/escolher_card_sugerido.dart mobile/test/features/biofeedback/escolher_card_sugerido_test.dart
git commit -m "feat(biofeedback): add pure grounding-card suggestion picker"
```

---

### Task 2: `BiofeedbackAlertService` — card-aware notification content

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_alert_service.dart`
- Test: `mobile/test/features/biofeedback/biofeedback_alert_service_test.dart`

**Interfaces:**
- Consumes: `GroundingCard` (`id`, `titulo`) from Task 1's file dependency (`../grounding_cards/grounding_card.dart`, already exists).
- Produces: `BiofeedbackAlertService.mostrarAlerta({GroundingCard? cardSugerido})`,
  `({String corpo, String payload}) construirConteudoAlerta({GroundingCard? cardSugerido})`,
  `String? BiofeedbackAlertService.extrairCardIdDoPayload(String? payload)` (static) — the last two
  consumed by Task 4 (indirectly, via `mostrarAlerta`) and Task 6 (`extrairCardIdDoPayload`,
  directly).

Current content of `mobile/lib/features/biofeedback/biofeedback_alert_service.dart`:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Usado tanto pelo `payload` desta notificação quanto pelo handler de toque em `main.dart`, para
/// os dois nunca ficarem dessincronizados.
const biofeedbackNotificationTapPayload = 'biofeedback_alerta';

const _idNotificacao = 100;
const _idCanalAndroid = 'biofeedback_alertas';
const _nomeCanalAndroid = 'Alertas de bem-estar';
const _tituloAlerta = 'Um momento para respirar';
const _corpoAlerta =
    'Sua frequência cardíaca está um pouco diferente do seu normal agora. '
    'Talvez seja um bom momento para uma pausa.';

class BiofeedbackAlertService {
  BiofeedbackAlertService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> mostrarAlerta() async {
    const detalhes = NotificationDetails(
      android: AndroidNotificationDetails(
        _idCanalAndroid,
        _nomeCanalAndroid,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      id: _idNotificacao,
      title: _tituloAlerta,
      body: _corpoAlerta,
      notificationDetails: detalhes,
      payload: biofeedbackNotificationTapPayload,
    );
  }
}
```

- [ ] **Step 1: Write the failing tests**

```dart
// mobile/test/features/biofeedback/biofeedback_alert_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_alert_service.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_card.dart';

GroundingCard _card({String id = 'card-1', String titulo = 'Respiração 4-7-8'}) => GroundingCard(
      id: id,
      titulo: titulo,
      categoria: 'RESPIRACAO',
      conteudo: 'Conteúdo',
      ativo: true,
    );

void main() {
  group('construirConteudoAlerta', () {
    test('uses the generic body and bare payload when there is no suggested card', () {
      final resultado = construirConteudoAlerta();

      expect(
        resultado.corpo,
        'Sua frequência cardíaca está um pouco diferente do seu normal agora. '
        'Talvez seja um bom momento para uma pausa.',
      );
      expect(resultado.payload, biofeedbackNotificationTapPayload);
    });

    test('mentions the card title and encodes its id in the payload when present', () {
      final resultado = construirConteudoAlerta(
        cardSugerido: _card(id: 'card-42', titulo: 'Respiração 4-7-8'),
      );

      expect(resultado.corpo, 'Que tal experimentar Respiração 4-7-8 agora?');
      expect(resultado.payload, 'biofeedback_alerta:card-42');
    });
  });

  group('BiofeedbackAlertService.extrairCardIdDoPayload', () {
    test('returns null for a null payload', () {
      expect(BiofeedbackAlertService.extrairCardIdDoPayload(null), isNull);
    });

    test('returns null for a payload unrelated to this alert type', () {
      expect(BiofeedbackAlertService.extrairCardIdDoPayload('email_triage'), isNull);
    });

    test('returns null for the bare prefix with no card id', () {
      expect(BiofeedbackAlertService.extrairCardIdDoPayload('biofeedback_alerta'), isNull);
    });

    test('returns the id when the payload has the prefix and a card id', () {
      expect(
        BiofeedbackAlertService.extrairCardIdDoPayload('biofeedback_alerta:card-42'),
        'card-42',
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_alert_service_test.dart`
Expected: FAIL — `construirConteudoAlerta` and `BiofeedbackAlertService.extrairCardIdDoPayload` are
undefined.

- [ ] **Step 3: Write the implementation**

Replace the full content of `mobile/lib/features/biofeedback/biofeedback_alert_service.dart` with:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../grounding_cards/grounding_card.dart';

/// Usado tanto pelo `payload` desta notificação quanto pelo handler de toque em `main.dart`, para
/// os dois nunca ficarem dessincronizados.
const biofeedbackNotificationTapPayload = 'biofeedback_alerta';

const _idNotificacao = 100;
const _idCanalAndroid = 'biofeedback_alertas';
const _nomeCanalAndroid = 'Alertas de bem-estar';
const _tituloAlerta = 'Um momento para respirar';
const _corpoAlerta =
    'Sua frequência cardíaca está um pouco diferente do seu normal agora. '
    'Talvez seja um bom momento para uma pausa.';

/// Corpo e payload da notificação de alerta, extraídos de `mostrarAlerta` para serem testáveis
/// sem tocar `FlutterLocalNotificationsPlugin` (não há precedente de mock desse plugin neste
/// projeto). Sem `cardSugerido`, mantém o texto genérico e o payload de sempre; com ele, menciona
/// o título do card (não é dado de saúde — conteúdo público/curado) e encapsula o id no payload.
({String corpo, String payload}) construirConteudoAlerta({GroundingCard? cardSugerido}) {
  final corpo = cardSugerido != null
      ? 'Que tal experimentar ${cardSugerido.titulo} agora?'
      : _corpoAlerta;
  final payload = cardSugerido != null
      ? '$biofeedbackNotificationTapPayload:${cardSugerido.id}'
      : biofeedbackNotificationTapPayload;
  return (corpo: corpo, payload: payload);
}

class BiofeedbackAlertService {
  BiofeedbackAlertService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> mostrarAlerta({GroundingCard? cardSugerido}) async {
    const detalhes = NotificationDetails(
      android: AndroidNotificationDetails(
        _idCanalAndroid,
        _nomeCanalAndroid,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
    final conteudo = construirConteudoAlerta(cardSugerido: cardSugerido);
    await _plugin.show(
      id: _idNotificacao,
      title: _tituloAlerta,
      body: conteudo.corpo,
      notificationDetails: detalhes,
      payload: conteudo.payload,
    );
  }

  /// Extrai o id do card sugerido de um payload de notificação, se houver. `null` para payload
  /// nulo, para um payload de outro tipo de notificação, e para o prefixo sem id (alerta sem
  /// card sugerido).
  static String? extrairCardIdDoPayload(String? payload) {
    if (payload == null) return null;
    if (!payload.startsWith(biofeedbackNotificationTapPayload)) return null;
    final resto = payload.substring(biofeedbackNotificationTapPayload.length);
    if (!resto.startsWith(':')) return null;
    final id = resto.substring(1);
    return id.isEmpty ? null : id;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_alert_service_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Run the full biofeedback test directory to check for regressions**

Run: `cd mobile && flutter test test/features/biofeedback/`
Expected: PASS for every file except `biofeedback_sync_service_test.dart`, which is expected to
fail here — it still calls the old `mostrarAlerta()` zero-arg stub/verify shape and gets fixed in
Task 4. Confirm the failures are only in that one file before continuing.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_alert_service.dart mobile/test/features/biofeedback/biofeedback_alert_service_test.dart
git commit -m "feat(biofeedback): mention suggested grounding card in the alert notification"
```

---

### Task 3: `resolverCardSugerido` pure function

**Files:**
- Create: `mobile/lib/features/grounding_cards/resolver_card_sugerido.dart`
- Test: `mobile/test/features/grounding_cards/resolver_card_sugerido_test.dart`

**Interfaces:**
- Produces: `GroundingCard? resolverCardSugerido({required List<GroundingCard> cards, required String id})` — consumed by Task 6.

- [ ] **Step 1: Write the failing tests**

```dart
// mobile/test/features/grounding_cards/resolver_card_sugerido_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_card.dart';
import 'package:sincro_mobile/features/grounding_cards/resolver_card_sugerido.dart';

GroundingCard _card(String id) => GroundingCard(
      id: id,
      titulo: 'Card $id',
      categoria: 'RESPIRACAO',
      conteudo: 'Conteúdo',
      ativo: true,
    );

void main() {
  test('returns the card whose id matches', () {
    final cards = [_card('a'), _card('b'), _card('c')];

    final resultado = resolverCardSugerido(cards: cards, id: 'b');

    expect(resultado?.id, 'b');
  });

  test('returns null when no card matches the id', () {
    final cards = [_card('a'), _card('b')];

    final resultado = resolverCardSugerido(cards: cards, id: 'z');

    expect(resultado, isNull);
  });

  test('returns null for an empty list', () {
    final resultado = resolverCardSugerido(cards: [], id: 'a');

    expect(resultado, isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd mobile && flutter test test/features/grounding_cards/resolver_card_sugerido_test.dart`
Expected: FAIL — `Target of URI doesn't exist:
'package:sincro_mobile/features/grounding_cards/resolver_card_sugerido.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// mobile/lib/features/grounding_cards/resolver_card_sugerido.dart
import 'grounding_card.dart';

/// Localiza, dentro de uma lista já buscada de cards, aquele cujo id corresponde ao sugerido por
/// uma notificação de Biofeedback. `null` quando não encontrado (card desativado/removido entre o
/// disparo do alerta e o toque, ou lista vazia).
GroundingCard? resolverCardSugerido({required List<GroundingCard> cards, required String id}) {
  for (final card in cards) {
    if (card.id == id) return card;
  }
  return null;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/grounding_cards/resolver_card_sugerido_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/grounding_cards/resolver_card_sugerido.dart mobile/test/features/grounding_cards/resolver_card_sugerido_test.dart
git commit -m "feat(grounding-cards): add pure card-by-id resolver for suggested-card deep links"
```

---

### Task 4: `BiofeedbackSyncService` — fetch and pass the suggested card

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_sync_service.dart`
- Modify: `mobile/test/features/biofeedback/biofeedback_sync_service_test.dart`

**Interfaces:**
- Consumes: `escolherCardSugerido`/`sortearIndiceAleatorio` (Task 1),
  `BiofeedbackAlertService.mostrarAlerta({GroundingCard? cardSugerido})` (Task 2),
  `GroundingCardsRepository` (`list({String? categoria})`, `listFavoritos()` — already exist,
  unchanged, in `mobile/lib/features/grounding_cards/grounding_cards_repository.dart`).
- Produces: `BiofeedbackSyncService`'s constructor now takes a 7th positional parameter,
  `GroundingCardsRepository groundingCardsRepository` — consumed by Task 5 (both instantiation
  sites).

Current constructor and imports of `mobile/lib/features/biofeedback/biofeedback_sync_service.dart`:

```dart
import 'biofeedback_alert_decision.dart';
import 'biofeedback_alert_service.dart';
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_stress_detector.dart';
import 'biofeedback_summary.dart';
import 'biofeedback_summary_calculator.dart';
import 'estado_estresse.dart';
import '../onboarding/anamnese/sensory_profile_repository.dart';

class BiofeedbackSyncService {
  BiofeedbackSyncService(
    this._healthService,
    this._cache,
    this._calculator,
    this._detector,
    this._alertService,
    this._sensoryProfileRepository,
  );

  final BiofeedbackHealthService _healthService;
  final BiofeedbackCache _cache;
  final BiofeedbackSummaryCalculator _calculator;
  final BiofeedbackStressDetector _detector;
  final BiofeedbackAlertService _alertService;
  final SensoryProfileRepository _sensoryProfileRepository;
```

Current `_notificarSeNecessario`:

```dart
  Future<void> _notificarSeNecessario({
    required EstadoEstresse? estadoAnterior,
    required EstadoEstresse estadoNovo,
  }) async {
    final transicaoRelevante =
        estadoAnterior != EstadoEstresse.elevado && estadoNovo == EstadoEstresse.elevado;
    if (!transicaoRelevante) return;

    final alertasAtivos = await _cache.getAlertasAtivos();
    if (!alertasAtivos) return;

    String? tolerancia;
    try {
      final dados = await _sensoryProfileRepository.get();
      tolerancia = dados?['toleranciaNotificacao'] as String?;
    } catch (_) {
      // Falha ao ler a preferência é tratada como "não notificar" (silencioso por padrão),
      // nunca como motivo para notificar mesmo sem saber a preferência do usuário.
      tolerancia = null;
    }

    if (deveAlertar(
      estadoAnterior: estadoAnterior,
      estadoNovo: estadoNovo,
      alertasAtivos: alertasAtivos,
      tolerancia: tolerancia,
    )) {
      await _alertService.mostrarAlerta();
    }
  }
```

- [ ] **Step 1: Update `buildService` and every `mostrarAlerta` assertion in the test file first (red)**

In `mobile/test/features/biofeedback/biofeedback_sync_service_test.dart`:

Add these imports alongside the existing ones:

```dart
import 'package:sincro_mobile/features/biofeedback/escolher_card_sugerido.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_card.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_cards_repository.dart';
```

Add a mock and a fake alongside the existing ones (right after `class MockSensoryProfileRepository extends Mock implements SensoryProfileRepository {}`):

```dart
class MockGroundingCardsRepository extends Mock implements GroundingCardsRepository {}

class FakeGroundingCard extends Fake implements GroundingCard {}
```

In `setUpAll`, register the new fallback value alongside the existing one:

```dart
void main() {
  setUpAll(() {
    registerFallbackValue(FakeBiofeedbackSummary());
    registerFallbackValue(FakeGroundingCard());
  });
```

Replace the `buildService` helper (adds a `groundingCardsRepository` param constructed internally
— no existing call site needs to change — plus three new optional lists for the two tests that
care about them):

```dart
  BiofeedbackSyncService buildService(
    MockBiofeedbackHealthService healthService,
    MockBiofeedbackCache cache,
    MockBiofeedbackAlertService alertService,
    MockSensoryProfileRepository sensoryProfileRepository, {
    List<HealthReading> passos = const [],
    List<TreinoIntervalo> treinos = const [],
    List<DiaRepouso> historico = const [],
    BiofeedbackSummary? resumoAnterior,
    bool ativo = true,
    int permissoesVersao = BiofeedbackCache.versaoPermissoesAtual,
    bool alertasAtivos = true,
    Map<String, dynamic>? perfilSensorial,
    List<GroundingCard> favoritosSugeridos = const [],
    List<GroundingCard> respiracaoAtivosSugeridos = const [],
    List<GroundingCard> todosAtivosSugeridos = const [],
    bool falharBuscaDeCards = false,
  }) {
    when(() => healthService.solicitarPermissao()).thenAnswer((_) async => true);
    when(() => healthService.lerPassosHoje()).thenAnswer((_) async => passos);
    when(() => healthService.lerTreinosHoje()).thenAnswer((_) async => treinos);
    when(() => cache.isAtivo()).thenAnswer((_) async => ativo);
    when(() => cache.getPermissoesVersao()).thenAnswer((_) async => permissoesVersao);
    when(() => cache.setPermissoesVersao(any())).thenAnswer((_) async {});
    when(() => cache.getHistoricoRepouso()).thenAnswer((_) async => historico);
    when(() => cache.setHistoricoRepouso(any())).thenAnswer((_) async {});
    when(() => cache.getResumo()).thenAnswer((_) async => resumoAnterior);
    when(() => cache.setResumo(any())).thenAnswer((_) async {});
    when(() => cache.getAlertasAtivos()).thenAnswer((_) async => alertasAtivos);
    when(() => sensoryProfileRepository.get()).thenAnswer((_) async => perfilSensorial);
    when(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido')))
        .thenAnswer((_) async {});
    final groundingCardsRepository = MockGroundingCardsRepository();
    if (falharBuscaDeCards) {
      final erro = Exception('rede indisponível');
      when(() => groundingCardsRepository.listFavoritos()).thenThrow(erro);
      when(() => groundingCardsRepository.list(categoria: 'RESPIRACAO')).thenThrow(erro);
      when(() => groundingCardsRepository.list()).thenThrow(erro);
    } else {
      when(() => groundingCardsRepository.listFavoritos())
          .thenAnswer((_) async => favoritosSugeridos);
      when(() => groundingCardsRepository.list(categoria: 'RESPIRACAO'))
          .thenAnswer((_) async => respiracaoAtivosSugeridos);
      when(() => groundingCardsRepository.list())
          .thenAnswer((_) async => todosAtivosSugeridos);
    }
    return BiofeedbackSyncService(
      healthService,
      cache,
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
      alertService,
      sensoryProfileRepository,
      groundingCardsRepository,
    );
  }
```

Update the one existing assertion that checks the alert fired (currently
`verify(() => alertService.mostrarAlerta()).called(1);`, in the `'sends the alert when the state
transitions into elevado with tolerancia PADRAO'` test) to:

```dart
    verify(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido'))).called(1);
```

Update every one of the five existing `verifyNever(() => alertService.mostrarAlerta());` lines
(in `'does not send the alert when already elevado before this cycle'`, `'does not send the alert
or read the sensory profile when the resulting state is not elevado'`, `'does not send the alert
when alertasAtivos is false, and skips the network read'`, `'does not send the alert when
tolerancia is not PADRAO'`, and `'treats a failed sensory-profile read as no-alert rather than
throwing'`) to:

```dart
    verifyNever(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido')));
```

Add two new tests at the end of the top-level test group, right before the `group('upgrade de
permissões', ...)` block:

```dart
  test('includes a favorited card in the alert body when the state transitions into elevado', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final favorito = GroundingCard(
      id: 'fav-1',
      titulo: 'Respiração 4-7-8',
      categoria: 'RESPIRACAO',
      conteudo: 'Conteúdo',
      ativo: true,
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 70,
        mediaVfcHoje: 45,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
      favoritosSugeridos: [favorito],
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    final captured =
        verify(() => alertService.mostrarAlerta(cardSugerido: captureAny(named: 'cardSugerido')))
            .captured;
    final cardSugerido = captured.single as GroundingCard?;
    expect(cardSugerido?.id, 'fav-1');
  });

  test('alerts with no suggested card when every grounding-card lookup fails', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 70,
        mediaVfcHoje: 45,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
      falharBuscaDeCards: true,
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    final captured =
        verify(() => alertService.mostrarAlerta(cardSugerido: captureAny(named: 'cardSugerido')))
            .captured;
    expect(captured.single, isNull);
  });
```

- [ ] **Step 2: Run the test file to verify it now fails on the production code, not the test file**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_sync_service_test.dart`
Expected: FAIL to compile — `Too many positional arguments: 6 expected, but 7 found` at both
`BiofeedbackSyncService(...)` call sites in the test file (`buildService` and the new second test),
since the constructor still only accepts 6 positional parameters at this point. Resolved by Step 3.

- [ ] **Step 3: Update the production code**

In `mobile/lib/features/biofeedback/biofeedback_sync_service.dart`, add two imports alongside the
existing ones:

```dart
import 'escolher_card_sugerido.dart';
import '../grounding_cards/grounding_card.dart';
import '../grounding_cards/grounding_cards_repository.dart';
```

Update the constructor and fields:

```dart
class BiofeedbackSyncService {
  BiofeedbackSyncService(
    this._healthService,
    this._cache,
    this._calculator,
    this._detector,
    this._alertService,
    this._sensoryProfileRepository,
    this._groundingCardsRepository,
  );

  final BiofeedbackHealthService _healthService;
  final BiofeedbackCache _cache;
  final BiofeedbackSummaryCalculator _calculator;
  final BiofeedbackStressDetector _detector;
  final BiofeedbackAlertService _alertService;
  final SensoryProfileRepository _sensoryProfileRepository;
  final GroundingCardsRepository _groundingCardsRepository;
```

Replace `_notificarSeNecessario` and add the two new private helpers right after it:

```dart
  Future<void> _notificarSeNecessario({
    required EstadoEstresse? estadoAnterior,
    required EstadoEstresse estadoNovo,
  }) async {
    final transicaoRelevante =
        estadoAnterior != EstadoEstresse.elevado && estadoNovo == EstadoEstresse.elevado;
    if (!transicaoRelevante) return;

    final alertasAtivos = await _cache.getAlertasAtivos();
    if (!alertasAtivos) return;

    String? tolerancia;
    try {
      final dados = await _sensoryProfileRepository.get();
      tolerancia = dados?['toleranciaNotificacao'] as String?;
    } catch (_) {
      // Falha ao ler a preferência é tratada como "não notificar" (silencioso por padrão),
      // nunca como motivo para notificar mesmo sem saber a preferência do usuário.
      tolerancia = null;
    }

    if (!deveAlertar(
      estadoAnterior: estadoAnterior,
      estadoNovo: estadoNovo,
      alertasAtivos: alertasAtivos,
      tolerancia: tolerancia,
    )) {
      return;
    }

    final cardSugerido = await _buscarCardSugerido();
    await _alertService.mostrarAlerta(cardSugerido: cardSugerido);
  }

  /// Escolhe um grounding card para sugerir junto do alerta (favoritos > categoria Respiração >
  /// qualquer card ativo). Cada busca é best-effort — uma falha em qualquer uma delas vira lista
  /// vazia, nunca uma exceção que impediria o alerta em si de disparar.
  Future<GroundingCard?> _buscarCardSugerido() async {
    final favoritos = await _listaSeguraDeCards(_groundingCardsRepository.listFavoritos);
    final respiracaoAtivos = await _listaSeguraDeCards(
      () => _groundingCardsRepository.list(categoria: 'RESPIRACAO'),
    );
    final todosAtivos = await _listaSeguraDeCards(_groundingCardsRepository.list);

    final cardId = escolherCardSugerido(
      favoritos: favoritos,
      respiracaoAtivos: respiracaoAtivos,
      todosAtivos: todosAtivos,
      sortear: sortearIndiceAleatorio,
    );
    if (cardId == null) return null;

    return [...favoritos, ...respiracaoAtivos, ...todosAtivos]
        .firstWhere((card) => card.id == cardId);
  }

  Future<List<GroundingCard>> _listaSeguraDeCards(
    Future<List<GroundingCard>> Function() buscar,
  ) async {
    try {
      return await buscar();
    } catch (_) {
      return const [];
    }
  }
```

- [ ] **Step 4: Run the test file to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_sync_service_test.dart`
Expected: PASS (all tests, including the 2 new ones).

- [ ] **Step 5: Run the whole biofeedback test directory to confirm no other regression**

Run: `cd mobile && flutter test test/features/biofeedback/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_sync_service.dart mobile/test/features/biofeedback/biofeedback_sync_service_test.dart
git commit -m "feat(biofeedback): pick and pass a suggested grounding card into the stress alert"
```

---

### Task 5: Wire `GroundingCardsRepository` into both instantiation sites

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_background_task.dart`
- Modify: `mobile/lib/features/biofeedback/biofeedback_providers.dart`

**Interfaces:**
- Consumes: `BiofeedbackSyncService`'s new 7-arg constructor (Task 4); `GroundingCardsRepository`
  (constructor `GroundingCardsRepository(Dio dio)`, already exists); `groundingCardsRepositoryProvider`
  (already exists in `mobile/lib/features/grounding_cards/grounding_cards_providers.dart`).

No new tests in this task — both changes are one-line constructor-call additions to code that
already has no direct unit test (the background dispatcher is documented as manual-verification
only in the Fase 3 spec; the provider wiring is exercised indirectly by every existing Biofeedback
widget/provider test that already passes).

- [ ] **Step 1: Update the background isolate's dispatcher**

In `mobile/lib/features/biofeedback/biofeedback_background_task.dart`, add an import:

```dart
import '../grounding_cards/grounding_cards_repository.dart';
```

Change the `syncService` construction inside `biofeedbackCallbackDispatcher`:

```dart
    final syncService = BiofeedbackSyncService(
      BiofeedbackHealthService(),
      BiofeedbackCache(),
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
      BiofeedbackAlertService(FlutterLocalNotificationsPlugin()),
      SensoryProfileRepository(dio),
      GroundingCardsRepository(dio),
    );
```

(`dio` is the same variable already built a few lines above, shared with
`SensoryProfileRepository(dio)` — same fallback-to-unauthenticated-Dio behavior applies equally to
grounding-card lookups if `Firebase.initializeApp()` failed in this isolate.)

- [ ] **Step 2: Update the foreground Riverpod provider**

In `mobile/lib/features/biofeedback/biofeedback_providers.dart`, add an import:

```dart
import '../grounding_cards/grounding_cards_providers.dart' show groundingCardsRepositoryProvider;
```

Change `biofeedbackSyncServiceProvider`:

```dart
final biofeedbackSyncServiceProvider = Provider<BiofeedbackSyncService>((ref) {
  return BiofeedbackSyncService(
    ref.watch(biofeedbackHealthServiceProvider),
    ref.watch(biofeedbackCacheProvider),
    BiofeedbackSummaryCalculator(),
    BiofeedbackStressDetector(),
    ref.watch(biofeedbackAlertServiceProvider),
    ref.watch(sensoryProfileRepositoryProvider),
    ref.watch(groundingCardsRepositoryProvider),
  );
});
```

- [ ] **Step 3: Run `flutter analyze` to confirm both files compile clean**

Run: `cd mobile && flutter analyze lib/features/biofeedback/biofeedback_background_task.dart lib/features/biofeedback/biofeedback_providers.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the full mobile test suite to confirm nothing else broke**

Run: `cd mobile && flutter test`
Expected: PASS, same total count as before this task plus the 8 new tests from Tasks 1-4 (5 +
6 + 3 + 2 = 16 new tests; exact prior total can be read off the last `flutter test` output before
this plan started).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_background_task.dart mobile/lib/features/biofeedback/biofeedback_providers.dart
git commit -m "feat(biofeedback): wire GroundingCardsRepository into both sync-service call sites"
```

---

### Task 6: `GroundingCardSugeridoScreen` + route + tap-handler update

**Files:**
- Create: `mobile/lib/features/grounding_cards/grounding_card_sugerido_screen.dart`
- Modify: `mobile/lib/main.dart`

**Interfaces:**
- Consumes: `resolverCardSugerido` (Task 3); `groundingCardsProvider(String? categoria)` and
  `groundingCardFavoritosProvider` (already exist in
  `mobile/lib/features/grounding_cards/grounding_cards_providers.dart`);
  `GroundingCardDetailScreen({required GroundingCard card, required bool favoritadoInicial})`
  (already exists); `BiofeedbackAlertService.extrairCardIdDoPayload` (Task 2);
  `biofeedbackNotificationTapPayload` (already exists).

No automated test for this task — it's exactly the combination the Global Constraints section
calls out as manual-verification-only: a grounding-cards screen (no `pumpWidget` convention in
this codebase) driven by `main.dart`'s global-dependent tap handler (no unit-test precedent
either). The pure logic each of them delegates to (`resolverCardSugerido`,
`extrairCardIdDoPayload`) is already covered by Tasks 2 and 3.

- [ ] **Step 1: Create the connector screen**

```dart
// mobile/lib/features/grounding_cards/grounding_card_sugerido_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'grounding_card_detail_screen.dart';
import 'grounding_cards_providers.dart';
import 'resolver_card_sugerido.dart';

/// Elo entre a notificação de alerta do Biofeedback e a tela de detalhe de um grounding card: lê
/// o id recebido como argumento de rota, localiza o card na lista já mantida pelas providers
/// existentes e mostra o detalhe — ou cai silenciosamente para `/biofeedback` se o card não for
/// encontrado (desativado/removido entre o disparo do alerta e o toque) ou a busca falhar.
class GroundingCardSugeridoScreen extends ConsumerWidget {
  const GroundingCardSugeridoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardId = ModalRoute.of(context)!.settings.arguments as String;
    final cardsAsync = ref.watch(groundingCardsProvider(null));
    final favoritosAsync = ref.watch(groundingCardFavoritosProvider);

    return cardsAsync.when(
      data: (cards) {
        final card = resolverCardSugerido(cards: cards, id: cardId);
        if (card == null) return const _RedirectToBiofeedback();

        final favoritosIds = favoritosAsync.maybeWhen(
          data: (favoritos) => favoritos.map((c) => c.id).toSet(),
          orElse: () => const <String>{},
        );
        return GroundingCardDetailScreen(
          card: card,
          favoritadoInicial: favoritosIds.contains(card.id),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _RedirectToBiofeedback(),
    );
  }
}

/// Mesmo padrão de redirecionamento pós-build já usado em `OnboardingRouterScreen`
/// (`features/onboarding/onboarding_router.dart`) — evita chamar `Navigator` durante `build()`.
class _RedirectToBiofeedback extends StatefulWidget {
  const _RedirectToBiofeedback();

  @override
  State<_RedirectToBiofeedback> createState() => _RedirectToBiofeedbackState();
}

class _RedirectToBiofeedbackState extends State<_RedirectToBiofeedback> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed('/biofeedback');
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
```

- [ ] **Step 2: Register the route and update the tap handler in `main.dart`**

Add an import alongside the existing grounding-cards imports:

```dart
import 'features/grounding_cards/grounding_card_sugerido_screen.dart';
```

Add the new route to the `routes:` map, right after `'/grounding-cards':`:

```dart
        '/grounding-cards': (_) => const GroundingCardsLibraryScreen(),
        '/grounding-cards/sugerido': (_) => const GroundingCardSugeridoScreen(),
```

Replace `_handleBiofeedbackAlertTap`:

```dart
/// Toque numa notificação de alerta do Biofeedback com o app aberto ou em background navega para
/// o card de aterramento sugerido (quando o alerta veio com um) ou para a tela de detalhe do
/// Biofeedback (quando não veio, ou o payload é de outro tipo de notificação local que este app
/// venha a ter no futuro). Só navega com uma sessão válida — do contrário um toque deslogado (ex.:
/// alerta disparado em background e só tocado depois de um logout) empurraria uma dessas rotas por
/// cima de /login, igual ao guard de _handleEmailTriageNotificationTap acima.
///
/// Não cobre cold-start (app terminado): `onDidReceiveNotificationResponse` nunca dispara nesse
/// caso — ver o uso de `getNotificationAppLaunchDetails()` em `main()`, que trata esse cenário
/// separadamente, no mesmo espírito do `getInitialMessage()` do FCM acima.
void _handleBiofeedbackAlertTap(NotificationResponse response) {
  if (!(response.payload?.startsWith(biofeedbackNotificationTapPayload) ?? false)) return;
  if (FirebaseAuth.instance.currentUser == null) return;

  final cardId = BiofeedbackAlertService.extrairCardIdDoPayload(response.payload);
  if (cardId == null) {
    navigatorKey.currentState?.pushNamed('/biofeedback');
    return;
  }
  navigatorKey.currentState?.pushNamed('/grounding-cards/sugerido', arguments: cardId);
}
```

- [ ] **Step 3: Run `flutter analyze` on the whole project**

Run: `cd mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Run the full test suite one more time**

Run: `cd mobile && flutter test`
Expected: PASS, same count as the end of Task 5 (this task adds no new automated tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/grounding_cards/grounding_card_sugerido_screen.dart mobile/lib/main.dart
git commit -m "feat(biofeedback): open the suggested grounding card directly from the alert notification"
```

---

### Task 7: Manual verification (device required)

Not automatable in `flutter test` — same category as the manual-verification items already
documented in every Biofeedback-pilar spec (permission dialogs, background scheduling, real
notification delivery). Requires a real Android or iOS device with the app installed and, ideally,
at least one grounding card seeded in the database (via the admin screen or directly, same
technique already used earlier for visual QA of this app) so a suggestion is actually available to
show.

- [ ] **Step 1:** With no favorited cards and no `RESPIRACAO`-category card active, force a
  transition to `elevado` (or wait for one) and confirm the alert still fires with the original
  generic body, and tapping it opens `/biofeedback` — the no-card fallback path.
- [ ] **Step 2:** Activate at least one card in the `RESPIRACAO` category (via the admin screen),
  repeat the transition, and confirm the notification body now says `"Que tal experimentar
  <título> agora?"`.
- [ ] **Step 3:** Favorite a different, non-`RESPIRACAO` card from the library, repeat the
  transition, and confirm the notification now mentions the favorited card instead (priority
  order holds).
- [ ] **Step 4:** Tap the notification with the app fully closed, with it backgrounded, and with
  it open in each case confirm it lands on that exact card's detail screen, not the library and
  not `/biofeedback`.
- [ ] **Step 5:** Deactivate that same favorited card from the admin screen immediately after a new
  alert fires (before tapping it), then tap the stale notification — confirm it falls back to
  `/biofeedback` instead of crashing or showing a blank screen.
- [ ] **Step 6:** Toggle the device to airplane mode right before a transition to `elevado`, let
  the alert fire, and confirm it still fires (with the generic body, no crash) despite every
  grounding-card lookup failing.

---

## Self-Review Notes

- **Spec coverage:** every numbered item in the spec's "Objetivo desta fase" and every subsection
  of "Arquitetura" maps to a task above (card selection → Task 1; notification content →
  Task 2; navigation resolution → Task 3 + Task 6; sync-service wiring → Task 4 + Task 5). The
  spec's "Testes" section maps 1:1 to the test steps in Tasks 1-4 plus the manual checklist in
  Task 7.
- **Placeholder scan:** no TBD/TODO; every code step has literal, complete code. `buildService`
  gained a `falharBuscaDeCards` flag specifically so the "every lookup fails" test in Task 4 can
  reuse it like every other test instead of duplicating its ~15 lines of unrelated stubbing.
- **Type consistency:** `escolherCardSugerido`'s `sortear` parameter, `GroundingCardsRepository`'s
  `list`/`listFavoritos` signatures, `GroundingCard.id`/`.titulo`, and
  `BiofeedbackAlertService.mostrarAlerta`'s `cardSugerido` parameter name are used identically
  across every task that touches them.
