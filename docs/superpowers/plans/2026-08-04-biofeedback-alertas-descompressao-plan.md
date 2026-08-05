# Biofeedback & Crise — Alertas de Descompressão (Fase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the on-device `BiofeedbackStressDetector` (Fase 2) detects the transition into an "elevado" state, fire a calm local device notification — even when the app is closed and this happens during background sync — respecting the user's existing notification-tolerance preference and a new dedicated on/off toggle.

**Architecture:** Extends the existing `mobile/lib/features/biofeedback/` module. A new pure function (`deveAlertar`) decides whether to notify, given the previous/new stress state, the alerts-on/off toggle, and the notification-tolerance value. `BiofeedbackSyncService` captures the previous cached state before overwriting it, and — only when a real transition into "elevado" occurred and alerts are toggled on — reads the user's `toleranciaNotificacao` (the first network read this pillar has ever made; still zero writes of any health data) and, if `deveAlertar` says so, asks a thin `BiofeedbackAlertService` wrapper around `flutter_local_notifications` to show the notification. The background `workmanager` isolate gets its own Firebase initialization so it can make this same authenticated read.

**Tech Stack:** Flutter + Riverpod (existing), plus one new package: `flutter_local_notifications` — not yet a dependency of this project.

## Global Constraints

- No FC/VFC/passos/treino/estresse data ever leaves the device, in any direction. This phase's only network call is a READ of the user's already-existing `toleranciaNotificacao` preference (same call other pillars already make) — never a write, and never any biofeedback-derived value.
- Alert only on the transition from a non-`elevado` state (`calmo`, `coletandoDados`, or no prior summary at all) into `elevado`. Never on `elevado → elevado`, never on any transition away from `elevado`, never for `calmo`/`coletandoDados` themselves.
- No artificial cooldown/minimum-interval beyond the transition rule itself — a state that goes `elevado → calmo → elevado` again alerts again on the second transition.
- Only notify when `toleranciaNotificacao == 'PADRAO'` — any other value, including absent/`null`, is silent. Same rule the backend already applies for Gmail/Finanças (`backend/src/notifications/notification.service.ts`).
- The notification's title and body are fixed, calm, non-alarming strings with no interpolated numbers — exact text specified in Task 3.
- A dedicated "Alertas de estresse" toggle, independent of deactivating Biofeedback itself, defaults to `true`, and gates every alert alongside the transition/tolerance rules above.
- Deactivating Biofeedback (`BiofeedbackCache.clear()`) also erases the alerts-toggle state.

---

## Prerequisites

External uncertainty here is at least as high as Fase 1's `health`/`workmanager` integration (which had real, `flutter analyze`-invisible bugs caught only by an actual build) — this plan adds a brand-new package AND, for the first time in this pillar, touches Firebase Auth from inside the background `workmanager` isolate. Confirm these before/while working through the tasks below:

1. **`flutter_local_notifications` API surface.** This plan's `BiofeedbackAlertService` (Task 3) and `main.dart` wiring (Task 3) target a commonly-used shape of the package's API: `FlutterLocalNotificationsPlugin`, `.initialize(InitializationSettings(...), onDidReceiveNotificationResponse: ...)`, `AndroidInitializationSettings('@mipmap/ic_launcher')`, `DarwinInitializationSettings()`, `.show(id, title, body, NotificationDetails(android: AndroidNotificationDetails(...), iOS: DarwinNotificationDetails()), payload: ...)`, and `NotificationResponse.payload` in the tap callback. Confirm these exact names against whatever version `flutter pub add flutter_local_notifications` resolves — adjust Task 3 if they differ. This does not block Tasks 1-2 (the pure decision function and the cache flag), which don't depend on this package at all.
2. **Android 13+ runtime notification permission.** This plan's Task 3 requests it via
   `flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission()`
   — confirm this method name against the resolved version's Android implementation class, and confirm whether `AndroidManifest.xml` also needs an explicit `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />` line (likely yes, for Android 13/API 33+) in addition to the runtime request.
3. **Firebase in the background isolate.** `workmanager`'s background isolate (`biofeedbackCallbackDispatcher` in `biofeedback_background_task.dart`) has never previously touched Firebase — Fase 1/2's background work only used `BiofeedbackHealthService`/`BiofeedbackCache`, neither of which needs it. This phase's tolerance read needs an authenticated `Dio` (via `ApiClient`, which needs `FirebaseAuth.instance`), which needs `Firebase.initializeApp()` to have run in THIS isolate specifically — `main()`'s call to `Firebase.initializeApp()` does not carry over, since `workmanager` spawns a fresh Dart VM that only runs the registered callback, not `main()`. Task 5 guards this with `if (Firebase.apps.isEmpty) { await Firebase.initializeApp(...) }`, but confirm this actually works inside a headless `workmanager` isolate on both platforms — if `Firebase.initializeApp()` throws or hangs there, the whole `sincronizar()` call (not just the alert) would be at risk, so Task 5's placement (see its Step 1) wraps it defensively.
4. **`flutter_local_notifications`'s own background-isolate requirements**, if any (some notification plugins need a top-level `@pragma('vm:entry-point')` background response handler, similar to `workmanager`'s existing requirement on `biofeedbackCallbackDispatcher`) — check the resolved version's README for whether `.show()` alone (no response handling) works from a background isolate without extra setup, since this phase never needs to *handle* a tap from that isolate (the isolate is ephemeral and exits right after `executeTask` returns — a tap is handled by whatever process is running at tap time, which re-enters `main()`).

---

## Task 1: Alert decision — pure `deveAlertar` function

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_alert_decision.dart`
- Test: `mobile/test/features/biofeedback/biofeedback_alert_decision_test.dart`

**Interfaces:**
- Consumes: `EstadoEstresse` (already exists from Fase 2, in `estado_estresse.dart`).
- Produces: top-level function `deveAlertar({required EstadoEstresse? estadoAnterior, required EstadoEstresse estadoNovo, required bool alertasAtivos, required String? tolerancia}): bool`. Consumed by Task 4 (sync service).

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/features/biofeedback/biofeedback_alert_decision_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_alert_decision.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';

void main() {
  test('alerts on the transition from calmo to elevado', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, true);
  });

  test('alerts on the transition from coletandoDados to elevado', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.coletandoDados,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, true);
  });

  test('alerts when there was no previous summary at all (estadoAnterior null)', () {
    final resultado = deveAlertar(
      estadoAnterior: null,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, true);
  });

  test('does not alert when already elevado (elevado to elevado)', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.elevado,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, false);
  });

  test('does not alert when leaving elevado (elevado to calmo)', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.elevado,
      estadoNovo: EstadoEstresse.calmo,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, false);
  });

  test('does not alert when the new state is not elevado (calmo to calmo)', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.calmo,
      alertasAtivos: true,
      tolerancia: 'PADRAO',
    );

    expect(resultado, false);
  });

  test('does not alert when alertasAtivos is false, even on a valid transition', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: false,
      tolerancia: 'PADRAO',
    );

    expect(resultado, false);
  });

  test('does not alert when tolerancia is not PADRAO, even on a valid transition', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: 'HORARIO_ESPECIFICO',
    );

    expect(resultado, false);
  });

  test('does not alert when tolerancia is null', () {
    final resultado = deveAlertar(
      estadoAnterior: EstadoEstresse.calmo,
      estadoNovo: EstadoEstresse.elevado,
      alertasAtivos: true,
      tolerancia: null,
    );

    expect(resultado, false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_alert_decision_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package '.../biofeedback_alert_decision.dart'`

- [ ] **Step 3: Write minimal implementation**

Create `mobile/lib/features/biofeedback/biofeedback_alert_decision.dart`:

```dart
import 'estado_estresse.dart';

bool deveAlertar({
  required EstadoEstresse? estadoAnterior,
  required EstadoEstresse estadoNovo,
  required bool alertasAtivos,
  required String? tolerancia,
}) {
  if (estadoAnterior == EstadoEstresse.elevado) return false;
  if (estadoNovo != EstadoEstresse.elevado) return false;
  if (!alertasAtivos) return false;
  return tolerancia == 'PADRAO';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_alert_decision_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_alert_decision.dart mobile/test/features/biofeedback/biofeedback_alert_decision_test.dart
git commit -m "feat: add pure deveAlertar decision function for stress alerts"
```

---

## Task 2: Cache — alerts-enabled flag

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_cache.dart`
- Modify: `mobile/test/features/biofeedback/biofeedback_cache_test.dart`

**Interfaces:**
- Produces (added to `BiofeedbackCache`): `getAlertasAtivos(): Future<bool>` (default `true`), `setAlertasAtivos(bool): Future<void>`; `clear()` extended to also erase this key. Consumed by Task 4 (sync service) and Task 6 (Settings toggle).

- [ ] **Step 1: Write the failing tests**

Add this test inside `main()` in `mobile/test/features/biofeedback/biofeedback_cache_test.dart`, after the existing `getPermissoesVersao`/`setPermissoesVersao`-related tests and before the final closing brace:

```dart
  test('getAlertasAtivos defaults to true when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    expect(await cache.getAlertasAtivos(), true);
  });

  test('setAlertasAtivos persists the flag for later reads', () async {
    final cache = BiofeedbackCache();

    await cache.setAlertasAtivos(false);

    expect(await cache.getAlertasAtivos(), false);
  });

  test('clear also resets alertasAtivos back to the default', () async {
    final cache = BiofeedbackCache();
    await cache.setAlertasAtivos(false);

    await cache.clear();

    expect(await cache.getAlertasAtivos(), true);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_cache_test.dart`
Expected: FAIL — `The method 'getAlertasAtivos' isn't defined for the type 'BiofeedbackCache'`

- [ ] **Step 3: Write the minimal implementation**

In `mobile/lib/features/biofeedback/biofeedback_cache.dart`, add this constant alongside the other `_chave*` constants near the top of the file:

```dart
const _chaveAlertasAtivos = 'biofeedback_alertas_ativos';
```

Add these two methods to the `BiofeedbackCache` class, alongside `getPermissoesVersao`/`setPermissoesVersao`:

```dart
  Future<bool> getAlertasAtivos() async {
    return await _prefs.getBool(_chaveAlertasAtivos) ?? true;
  }

  Future<void> setAlertasAtivos(bool ativos) {
    return _prefs.setBool(_chaveAlertasAtivos, ativos);
  }
```

Add this line inside `clear()`, alongside the other `_prefs.remove(...)` calls:

```dart
    await _prefs.remove(_chaveAlertasAtivos);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_cache_test.dart`
Expected: PASS (16 tests — 13 existing plus 3 new)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_cache.dart mobile/test/features/biofeedback/biofeedback_cache_test.dart
git commit -m "feat: add alertasAtivos flag to BiofeedbackCache"
```

---

## Task 3: Local notification wrapper and app-level wiring

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_alert_service.dart`
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `mobile/lib/main.dart`

**Interfaces:**
- Produces: `BiofeedbackAlertService` with `mostrarAlerta(): Future<void>`. Consumed by Task 4 (sync service, foreground) and Task 5 (background dispatcher).
- Produces: top-level function `biofeedbackNotificationTapPayload = 'biofeedback_alerta'` (a shared string constant both the service and `main.dart`'s tap handler reference, so they can never drift apart) — put this in `biofeedback_alert_service.dart` alongside the class.

This file wraps a native platform plugin — same situation as Fase 1's `BiofeedbackHealthService`, no automated test. Verified via `flutter analyze` plus the manual device check called out in the spec's Testes section.

- [ ] **Step 1: Add the dependency**

Run: `cd mobile && flutter pub add flutter_local_notifications`
Expected: `mobile/pubspec.yaml` gains one new entry under `dependencies:` and `mobile/pubspec.lock` updates. Note the exact version pub resolves — per this plan's Prerequisites, confirm the API used below against it.

- [ ] **Step 2: Add the Android runtime notification permission**

Edit `mobile/android/app/src/main/AndroidManifest.xml` — add this line as a sibling of the existing `<uses-permission>` entries at the top of the file (per this plan's Prerequisites, confirm this is still required for the resolved package version and Android target):

```xml
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

- [ ] **Step 3: Write the alert service**

Per Prerequisite 1, confirm the `flutter_local_notifications` package's actual API against what's resolved in `mobile/pubspec.lock` before treating this as final.

Create `mobile/lib/features/biofeedback/biofeedback_alert_service.dart`:

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
      _idNotificacao,
      _tituloAlerta,
      _corpoAlerta,
      detalhes,
      payload: biofeedbackNotificationTapPayload,
    );
  }
}
```

- [ ] **Step 4: Wire plugin initialization and tap navigation into `main.dart`**

Per Prerequisite 1, confirm `flutter_local_notifications`'s actual `initialize`/callback API against the resolved version before treating this as final.

Add these imports to `mobile/lib/main.dart`, alongside the existing ones:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'features/biofeedback/biofeedback_alert_service.dart';
```

Add this top-level instance near the existing `navigatorKey` declaration:

```dart
final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
```

Add this function alongside the existing `_handleEmailTriageNotificationTap`:

```dart
/// Toque numa notificação de alerta do Biofeedback (app aberto, em background, ou cold-start)
/// navega para a tela de detalhe. O discriminador de payload evita reagir a outros tipos de
/// notificação local que este app venha a ter no futuro.
void _handleBiofeedbackAlertTap(NotificationResponse? response) {
  if (response == null) return;
  if (response.payload != biofeedbackNotificationTapPayload) return;
  navigatorKey.currentState?.pushNamed('/biofeedback');
}
```

Inside `main()`, after `await Firebase.initializeApp(...)` and before the `FirebaseMessaging` listener setup, add:

```dart
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: _handleBiofeedbackAlertTap,
  );
  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
```

- [ ] **Step 5: Verify it compiles**

Run: `cd mobile && flutter analyze`
Expected: "No issues found!" — if the package's actual API differs from what's used above (per Prerequisite 1), fix the mismatches here until this is clean.

- [ ] **Step 6: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/android/app/src/main/AndroidManifest.xml mobile/lib/features/biofeedback/biofeedback_alert_service.dart mobile/lib/main.dart
git commit -m "feat: add flutter_local_notifications dependency and BiofeedbackAlertService"
```

---

## Task 4: Sync service — trigger the alert on a real transition

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_sync_service.dart`
- Modify: `mobile/test/features/biofeedback/biofeedback_sync_service_test.dart`

**Interfaces:**
- Consumes: `deveAlertar` (Task 1); `BiofeedbackCache.getAlertasAtivos()` (Task 2); `BiofeedbackAlertService.mostrarAlerta()` (Task 3); `SensoryProfileRepository.get()` (already exists, in `mobile/lib/features/onboarding/anamnese/sensory_profile_repository.dart` — returns `Future<Map<String, dynamic>?>`, the raw `dados` blob, from which `dados['toleranciaNotificacao'] as String?` is read).
- Produces: `BiofeedbackSyncService`'s constructor gains two more positional parameters (`BiofeedbackAlertService`, `SensoryProfileRepository`), for a total of 6, in this exact order: health service, cache, calculator, detector, alert service, sensory profile repository. `sincronizar()`'s signature is unchanged. Consumed by Task 5 (providers, background task).

- [ ] **Step 1: Write the failing tests**

Replace the full contents of `mobile/test/features/biofeedback/biofeedback_sync_service_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_alert_service.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_cache.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_health_service.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_stress_detector.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary_calculator.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_sync_service.dart';
import 'package:sincro_mobile/features/biofeedback/dia_repouso.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';
import 'package:sincro_mobile/features/biofeedback/treino_intervalo.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/sensory_profile_repository.dart';

class MockBiofeedbackHealthService extends Mock implements BiofeedbackHealthService {}

class MockBiofeedbackCache extends Mock implements BiofeedbackCache {}

class MockBiofeedbackAlertService extends Mock implements BiofeedbackAlertService {}

class MockSensoryProfileRepository extends Mock implements SensoryProfileRepository {}

class FakeBiofeedbackSummary extends Fake implements BiofeedbackSummary {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeBiofeedbackSummary());
  });

  BiofeedbackSyncService buildService(
    MockBiofeedbackHealthService healthService,
    MockBiofeedbackCache cache,
    MockBiofeedbackAlertService alertService,
    MockSensoryProfileRepository sensoryProfileRepository, {
    List<HealthReading> passos = const [],
    List<TreinoIntervalo> treinos = const [],
    List<DiaRepouso> historico = const [],
    BiofeedbackSummary? resumoAnterior,
    bool alertasAtivos = true,
    Map<String, dynamic>? perfilSensorial,
  }) {
    when(() => healthService.lerPassosHoje()).thenAnswer((_) async => passos);
    when(() => healthService.lerTreinosHoje()).thenAnswer((_) async => treinos);
    when(() => cache.getHistoricoRepouso()).thenAnswer((_) async => historico);
    when(() => cache.setHistoricoRepouso(any())).thenAnswer((_) async {});
    when(() => cache.getResumo()).thenAnswer((_) async => resumoAnterior);
    when(() => cache.setResumo(any())).thenAnswer((_) async {});
    when(() => cache.getAlertasAtivos()).thenAnswer((_) async => alertasAtivos);
    when(() => sensoryProfileRepository.get()).thenAnswer((_) async => perfilSensorial);
    when(() => alertService.mostrarAlerta()).thenAnswer((_) async {});
    return BiofeedbackSyncService(
      healthService,
      cache,
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
      alertService,
      sensoryProfileRepository,
    );
  }

  List<DiaRepouso> historicoEstavelElevando() => [
        DiaRepouso(data: DateTime(2026, 7, 27), mediaFcRepouso: 66, mediaVfcRepouso: 50),
        DiaRepouso(data: DateTime(2026, 7, 28), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 7, 29), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 30), mediaFcRepouso: 72, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 31), mediaFcRepouso: 74, mediaVfcRepouso: 42),
        DiaRepouso(data: DateTime(2026, 8, 1), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 8, 2), mediaFcRepouso: 70, mediaVfcRepouso: 46),
      ];

  test('sends the alert when the state transitions into elevado with tolerancia PADRAO', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    final agora = DateTime(2026, 8, 3, 15, 0);
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
    );

    await service.sincronizar(agora: agora);

    verify(() => alertService.mostrarAlerta()).called(1);
  });

  test('does not send the alert when already elevado before this cycle', () async {
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
        ultimaFc: 110,
        mediaFcHoje: 110,
        mediaVfcHoje: 20,
        estadoEstresse: EstadoEstresse.elevado,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta());
  });

  test('does not send the alert or read the sensory profile when the resulting state is not elevado', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer((_) async => []);
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer((_) async => []);
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: null,
        mediaFcHoje: null,
        mediaVfcHoje: null,
        estadoEstresse: EstadoEstresse.coletandoDados,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta());
    // Sem transição para elevado, a leitura de rede nem deveria acontecer.
    verifyNever(() => sensoryProfileRepository.get());
  });

  test('does not send the alert when alertasAtivos is false, and skips the network read', () async {
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
      alertasAtivos: false,
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta());
    verifyNever(() => sensoryProfileRepository.get());
  });

  test('does not send the alert when tolerancia is not PADRAO', () async {
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
      perfilSensorial: {'toleranciaNotificacao': 'HORARIO_ESPECIFICO'},
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta());
  });

  test('treats a failed sensory-profile read as no-alert rather than throwing', () async {
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
    );
    when(() => sensoryProfileRepository.get()).thenThrow(Exception('rede indisponível'));

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta());
  });

  test('still saves the summary and history correctly alongside the alert logic', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 80, timestamp: DateTime(2026, 8, 3, 9, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 45, timestamp: DateTime(2026, 8, 3, 9, 0))],
    );
    final service = buildService(healthService, cache, alertService, sensoryProfileRepository);

    await service.sincronizar(agora: agora);

    final captured = verify(() => cache.setResumo(captureAny())).captured;
    final salvo = captured.single as BiofeedbackSummary;
    expect(salvo.ultimaFc, 80);
    expect(salvo.mediaFcHoje, 80);
    expect(salvo.mediaVfcHoje, 45);
    expect(salvo.atualizadoEm, agora);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_sync_service_test.dart`
Expected: FAIL — constructor `BiofeedbackSyncService` doesn't accept 6 positional arguments yet.

- [ ] **Step 3: Write the minimal implementation**

Replace the full contents of `mobile/lib/features/biofeedback/biofeedback_sync_service.dart` with:

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

  Future<void> sincronizar({DateTime? agora}) async {
    await _garantirPermissoesAtualizadas();

    final agoraEfetivo = agora ?? DateTime.now();
    final resumoAnterior = await _cache.getResumo();
    final leiturasFc = await _healthService.lerFrequenciaCardiacaHoje();
    final leiturasVfc = await _healthService.lerVariabilidadeHoje();
    final leiturasPassos = await _healthService.lerPassosHoje();
    final treinos = await _healthService.lerTreinosHoje();

    final resumoBase = _calculator.calcular(
      leiturasFc: leiturasFc,
      leiturasVfc: leiturasVfc,
      agora: agoraEfetivo,
    );

    final historicoAtual = await _cache.getHistoricoRepouso();
    final medias = _detector.mediasEmRepouso(
      leiturasFc: leiturasFc,
      leiturasVfc: leiturasVfc,
      leiturasPassos: leiturasPassos,
      treinos: treinos,
    );
    final estado = _detector.detectar(
      mediaFcRepousoHoje: medias.mediaFc,
      mediaVfcRepousoHoje: medias.mediaVfc,
      historico: historicoAtual,
      hoje: agoraEfetivo,
    );
    final historicoAtualizado = _detector.atualizarHistorico(
      historicoAtual: historicoAtual,
      hoje: agoraEfetivo,
      mediaFcRepousoHoje: medias.mediaFc,
      mediaVfcRepousoHoje: medias.mediaVfc,
    );

    await _cache.setResumo(
      BiofeedbackSummary(
        ultimaFc: resumoBase.ultimaFc,
        mediaFcHoje: resumoBase.mediaFcHoje,
        mediaVfcHoje: resumoBase.mediaVfcHoje,
        estadoEstresse: estado,
        atualizadoEm: resumoBase.atualizadoEm,
      ),
    );
    await _cache.setHistoricoRepouso(historicoAtualizado);

    await _notificarSeNecessario(
      estadoAnterior: resumoAnterior?.estadoEstresse,
      estadoNovo: estado,
    );
  }

  /// Só lê a rede (tolerância de notificação) quando as condições mais baratas já indicam uma
  /// transição real para "elevado" com os alertas ligados — evita uma chamada de rede a cada
  /// ciclo de sincronização quando não há nada para decidir.
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

  /// Pede as permissões que faltam para quem já usava o Biofeedback antes desta fase.
  ///
  /// `solicitarPermissao()` só roda na ativação, e quem ativou na Fase 1 já tem
  /// `biofeedback_ativo = true` — ou seja, nunca mais passaria por lá. Como a Fase 2 acrescentou
  /// PASSOS e TREINO ao conjunto pedido, esses usuários ficariam sem essas duas permissões, e a
  /// falha é silenciosa: o plugin `health` devolve lista vazia para um tipo não autorizado, então
  /// toda leitura pareceria "em repouso" e o dia inteiro (inclusive exercício) entraria na média
  /// que a linha de base usa — exatamente o que o filtro de atividade existe para evitar.
  ///
  /// Roda antes de qualquer leitura de saúde e vale tanto para a sincronização em primeiro plano
  /// quanto para a periódica em background, que é por onde a maioria dos usuários existentes
  /// passa primeiro depois da atualização.
  Future<void> _garantirPermissoesAtualizadas() async {
    if (!await _cache.isAtivo()) return;
    if (await _cache.getPermissoesVersao() >= BiofeedbackCache.versaoPermissoesAtual) return;

    try {
      await _healthService.solicitarPermissao();
    } catch (_) {
      // Best-effort, como o resto desta sincronização: uma falha ao pedir permissão não pode
      // impedir que os dados já autorizados sejam lidos e o resumo atualizado.
    }
    // Gravamos a versão independentemente do resultado (concedido, negado ou erro): insistir a
    // cada ciclo transformaria uma recusa deliberada em um pedido recorrente. Quem quiser
    // conceder depois ainda pode fazê-lo pelas configurações do app de saúde.
    await _cache.setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_sync_service_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_sync_service.dart mobile/test/features/biofeedback/biofeedback_sync_service_test.dart
git commit -m "feat: trigger stress alerts on transition into elevado"
```

---

## Task 5: Wire the alert service into providers and the background task

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_providers.dart`
- Modify: `mobile/lib/features/biofeedback/biofeedback_background_task.dart`

**Interfaces:**
- Consumes: `BiofeedbackAlertService`, `SensoryProfileRepository` (Task 3-4); `BiofeedbackSyncService`'s new 6-argument constructor (Task 4); `sensoryProfileRepositoryProvider`, `apiClientProvider` (already exist, in `mobile/lib/features/onboarding/anamnese/anamnese_providers.dart` and `mobile/lib/core/api_providers.dart`).
- Produces: `biofeedbackSyncServiceProvider` continues to expose the same `BiofeedbackSyncService` type, constructed with the two extra dependencies. No new provider names — nothing downstream needs to change because of this task.

No test for this file — pure dependency wiring, same reasoning as Fase 1/2's equivalent tasks.

- [ ] **Step 1: Update the providers file**

In `mobile/lib/features/biofeedback/biofeedback_providers.dart`, add these imports alongside the existing ones:

```dart
import 'biofeedback_alert_service.dart';
import '../onboarding/anamnese/anamnese_providers.dart' show sensoryProfileRepositoryProvider;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
```

Add this new provider, alongside `biofeedbackBackgroundTaskProvider`:

```dart
final biofeedbackAlertServiceProvider = Provider<BiofeedbackAlertService>((ref) {
  return BiofeedbackAlertService(FlutterLocalNotificationsPlugin());
});
```

Then change this exact block inside `biofeedbackSyncServiceProvider`:

```dart
final biofeedbackSyncServiceProvider = Provider<BiofeedbackSyncService>((ref) {
  return BiofeedbackSyncService(
    ref.watch(biofeedbackHealthServiceProvider),
    ref.watch(biofeedbackCacheProvider),
    BiofeedbackSummaryCalculator(),
    BiofeedbackStressDetector(),
  );
});
```

to:

```dart
final biofeedbackSyncServiceProvider = Provider<BiofeedbackSyncService>((ref) {
  return BiofeedbackSyncService(
    ref.watch(biofeedbackHealthServiceProvider),
    ref.watch(biofeedbackCacheProvider),
    BiofeedbackSummaryCalculator(),
    BiofeedbackStressDetector(),
    ref.watch(biofeedbackAlertServiceProvider),
    ref.watch(sensoryProfileRepositoryProvider),
  );
});
```

Also add this new provider, alongside `biofeedbackAtivoProvider`/`biofeedbackResumoProvider`, for Task 6's Settings toggle:

```dart
final biofeedbackAlertasAtivosProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(biofeedbackCacheProvider).getAlertasAtivos();
});
```

- [ ] **Step 2: Update the background task**

Per this plan's Prerequisite 3, the background isolate needs Firebase initialized before constructing anything Firebase-Auth-dependent (`ApiClient`/`SensoryProfileRepository`) — `main()`'s initialization does not carry over to this separate isolate.

Add these imports to `mobile/lib/features/biofeedback/biofeedback_background_task.dart`, alongside the existing ones:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'biofeedback_alert_service.dart';
import '../../core/api_client.dart';
import '../../core/api_providers.dart' show apiBaseUrl;
import '../../firebase_options.dart';
import '../onboarding/anamnese/sensory_profile_repository.dart';
```

Change this exact block inside `biofeedbackCallbackDispatcher`:

```dart
    if (task != biofeedbackTaskName) return true;
    final syncService = BiofeedbackSyncService(
      BiofeedbackHealthService(),
      BiofeedbackCache(),
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
    );
```

to:

```dart
    if (task != biofeedbackTaskName) return true;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    final apiClient = ApiClient(baseUrl: apiBaseUrl, firebaseAuth: FirebaseAuth.instance);
    final syncService = BiofeedbackSyncService(
      BiofeedbackHealthService(),
      BiofeedbackCache(),
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
      BiofeedbackAlertService(FlutterLocalNotificationsPlugin()),
      SensoryProfileRepository(apiClient.dio),
    );
```

- [ ] **Step 3: Verify it compiles**

Run: `cd mobile && flutter analyze`
Expected: "No issues found!" — if `Firebase.initializeApp()` or any of the new imports don't behave as expected inside this isolate context (per Prerequisite 3), this is the point to investigate and adjust.

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_providers.dart mobile/lib/features/biofeedback/biofeedback_background_task.dart
git commit -m "feat: wire BiofeedbackAlertService and sensory profile read into providers and background task"
```

---

## Task 6: Settings — alerts toggle

**Files:**
- Modify: `mobile/lib/features/settings/settings_screen.dart`

**Interfaces:**
- Consumes: `biofeedbackAlertasAtivosProvider`, `biofeedbackCacheProvider` (Task 5/2).

No automated test — same reasoning as this file's other Biofeedback settings tiles, this codebase doesn't widget-test its Settings dialogs; verified via `flutter analyze` and manual run.

- [ ] **Step 1: Watch the new provider in `build()`**

In `mobile/lib/features/settings/settings_screen.dart`'s `build()` method, add this line alongside the existing `final biofeedbackAtivo = ref.watch(biofeedbackAtivoProvider).maybeWhen(...)`:

```dart
    final biofeedbackAlertasAtivos = ref.watch(biofeedbackAlertasAtivosProvider).maybeWhen(
          data: (ativos) => ativos,
          orElse: () => true,
        );
```

- [ ] **Step 2: Add the toggle method**

Add this method inside `_SettingsScreenState`, alongside the existing `_editBiofeedbackFrequencia`/`_desativarBiofeedback` methods:

```dart
  Future<void> _alternarAlertasBiofeedback(bool valor) async {
    setState(() => _busy = true);
    try {
      await ref.read(biofeedbackCacheProvider).setAlertasAtivos(valor);
      ref.invalidate(biofeedbackAlertasAtivosProvider);
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
```

- [ ] **Step 3: Add the switch tile**

In `build()`, add this `SwitchListTile` to the `ListView`'s `children`, right after the existing "Frequência do Biofeedback" `ListTile` and before "Desativar Biofeedback" (still inside the `if (biofeedbackAtivo) ...[` block):

```dart
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Alertas de estresse'),
              value: biofeedbackAlertasAtivos,
              onChanged: _busy ? null : _alternarAlertasBiofeedback,
            ),
```

- [ ] **Step 4: Verify it compiles**

Run: `cd mobile && flutter analyze lib/features/settings/settings_screen.dart`
Expected: "No issues found!"

Then run the full mobile test suite to confirm nothing else broke: `cd mobile && flutter test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/settings/settings_screen.dart
git commit -m "feat: add stress-alerts toggle to Settings"
```

---

## Plan Self-Review Notes

**Spec coverage:**
- Notificação local na transição para "elevado", inclusive com o app fechado → Tasks 3, 4, 5 (`_notificarSeNecessario` roda dentro de `sincronizar()`, chamado tanto em primeiro plano quanto pelo `biofeedbackCallbackDispatcher`).
- Toque leva para `/biofeedback` → Task 3 (`_handleBiofeedbackAlertTap` em `main.dart`).
- Toggle independente em Configurações → Tasks 2, 5, 6.
- Respeita `toleranciaNotificacao` (só `'PADRAO'`) → Tasks 1, 4.
- Zero dado de saúde saindo do aparelho, só leitura da tolerância → confirmado por inspeção: nenhuma task deste plano grava nada no backend; `SensoryProfileRepository.get()` é a única chamada de rede introduzida, e é usada só para leitura.
- Texto fixo, sem números interpolados → Task 3 (`_tituloAlerta`/`_corpoAlerta` são constantes literais).
- `clear()` apaga a flag de alertas → Task 2.

**Placeholder scan:** No TBD/TODO. Task 3 (plugin de notificação) tem incerteza real de API documentada explicitamente nas Prerequisites — não é uma decisão faltando, é risco de integração de plataforma nomeado, mesmo padrão das Fases 1 e 2.

**Type consistency:** `deveAlertar` (Task 1) usado com a mesma assinatura em Task 4. `BiofeedbackCache.getAlertasAtivos`/`setAlertasAtivos` (Task 2) usados de forma idêntica em Tasks 4 e 6. `BiofeedbackAlertService.mostrarAlerta()` (Task 3) chamado sem argumentos em Task 4, consistente. `BiofeedbackSyncService`'s 6-parâmetro constructor (Task 4) usado na mesma ordem exata em Task 5's dois pontos de construção (provider e background dispatcher).

**Deferred (explicitly out of scope, from the approved spec):**
- Qualquer técnica de descompressão embutida (fica para o pilar "Comunidade & Alívio Sensorial").
- Cooldown/intervalo mínimo entre alertas além da própria regra de transição.
- Histórico de alertas na UI do app.
- Escrita de `toleranciaNotificacao` a partir deste pilar (permanece leitura apenas).
