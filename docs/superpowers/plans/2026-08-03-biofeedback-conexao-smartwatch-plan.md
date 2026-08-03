# Biofeedback & Crise — Conexão com Smartwatch (Fase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Sincro user activate Biofeedback, grant HealthKit/Health Connect permission, and see a calm on-device summary (latest heart rate, today's HR/HRV averages) refreshed both on demand and periodically in the background — with zero data leaving the device.

**Architecture:** This is the first Sincro pillar with no backend changes at all. Everything lives in a new `mobile/lib/features/biofeedback/` module: a thin wrapper around the `health` package for reading HealthKit/Health Connect data, a pure calculator that turns raw readings into a daily summary, a `shared_preferences`-backed local cache that the UI reads from (never reading `health` directly in a widget build), and a `workmanager`-scheduled background task that periodically re-runs the same read→calculate→cache pipeline the UI triggers on demand.

**Tech Stack:** Flutter + Riverpod (existing), plus three new packages: `health` (HealthKit/Health Connect unified API), `workmanager` (periodic background tasks), `shared_preferences` (local cache) — none of these are in `mobile/pubspec.yaml` yet.

## Global Constraints

- No FC/VFC (heart rate / heart rate variability) data touches the network or the backend — everything stays on-device (HealthKit/Health Connect + local `shared_preferences` cache). This pillar makes zero backend changes.
- The UI (Home card, detail screen) reads only from `BiofeedbackCache` — never calls the `health` package directly from a widget `build()`.
- Background refresh frequency is one of four pre-defined options only (15 min / 30 min / 1 hora / 2 horas) — never a free numeric input, since iOS/Android both have an effective ~15-minute floor for periodic background tasks and a free-form field would misrepresent the real precision available.
- Calm tone: no charts, no color-coded urgency — only the latest reading and today's averages, consistent with the rest of the app's non-anxiogenic design.
- The Home card is always visible (never hidden), same as every other pillar's card — its content changes based on activation/data state, the card itself never disappears.
- "Desativar" cancels the background task and clears the local cache, but cannot revoke the OS-level HealthKit/Health Connect permission — that's not something an app can do programmatically on either platform; the UI must say so.

---

## Prerequisites

External uncertainty is higher in this plan than in prior pillars, because it integrates directly with OS-level platform APIs this codebase has never touched before. Confirm these before/while working through the tasks below — each is called out again at the specific task it affects:

1. This plan's `BiofeedbackHealthService` (Task 4) targets a commonly-used shape of the `health` package's API (`Health()`, `requestAuthorization`, `getHealthDataFromTypes`, `HealthDataType.HEART_RATE`/`HEART_RATE_VARIABILITY_SDNN`, `NumericHealthValue`). Confirm these exact names against whatever version `flutter pub add health` resolves — package APIs can shift between major versions — and adjust the file if they differ. This does not block the tasks before it (models, calculator, cache), which don't depend on the `health` package at all.
2. This plan's `BiofeedbackBackgroundTask`/`main.dart` wiring (Task 6) targets a commonly-used shape of the `workmanager` package's API (`Workmanager().initialize(callback)`, `registerPeriodicTask`, `cancelByUniqueName`, `executeTask`). Confirm against the resolved version and adjust if needed.
3. Confirm the exact Health Connect permission strings and any additional `AndroidManifest.xml` entries (e.g. a `<queries>` block for the Health Connect package, an activity-alias for the permissions rationale screen) required by the installed `health` package version — check its README/setup instructions on pub.dev once it's added to this project. Task 1's manifest snippet is a reasonable starting point, not a verified-final one.
4. Enable the "HealthKit" capability for the iOS target in Xcode (Signing & Capabilities → + Capability → HealthKit) — this is a manual Xcode project step, not achievable by editing a text file, and is required for `NSHealthShareUsageDescription` to actually grant HealthKit access at runtime.
5. Confirm `android/app/build.gradle`'s `minSdkVersion` meets Health Connect's minimum requirement (check current `health`/Health Connect docs) and bump it if needed.

---

## Task 1: Dependencies, platform manifests, and core models

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/ios/Runner/Info.plist`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Create: `mobile/lib/features/biofeedback/health_reading.dart`
- Create: `mobile/lib/features/biofeedback/biofeedback_summary.dart`
- Create: `mobile/lib/features/biofeedback/biofeedback_frequencia.dart`
- Test: `mobile/test/features/biofeedback/biofeedback_summary_test.dart`

**Interfaces:**
- Produces: `HealthReading { valor: double, timestamp: DateTime }`; `BiofeedbackSummary { ultimaFc: double?, mediaFcHoje: double?, mediaVfcHoje: double?, atualizadoEm: DateTime }` with `toJson()`/`fromJson()`; `BiofeedbackFrequencia` enum with `.duracao` (Duration) and `.label` (String). Consumed by every later task in this plan.

- [x] **Step 1: Add dependencies**

Run: `cd mobile && flutter pub add health workmanager shared_preferences`
Expected: `mobile/pubspec.yaml` gains three new entries under `dependencies:` and `mobile/pubspec.lock` updates. Note the exact versions pub resolves — you'll need them if any later task's assumed API doesn't match (see Prerequisites 1-2).

- [x] **Step 2: Add the iOS HealthKit usage description**

Edit `mobile/ios/Runner/Info.plist` — add this key/value pair inside the top-level `<dict>` (alongside the existing keys, e.g. near `CFBundleName`):

```xml
	<key>NSHealthShareUsageDescription</key>
	<string>O Sincro usa dados de frequência cardíaca do seu smartwatch para mostrar um resumo calmo do seu bem-estar.</string>
```

- [x] **Step 3: Add Android Health Connect permissions**

Edit `mobile/android/app/src/main/AndroidManifest.xml` — add these two permission declarations as siblings of any existing `<uses-permission>` entries (or, if there are none yet, as the first children of `<manifest>`, before `<application>`):

```xml
    <uses-permission android:name="android.permission.health.READ_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_HEART_RATE_VARIABILITY" />
```

Per Prerequisite 3, confirm against the `health` package's own setup docs whether additional entries (a `<queries>` block, an activity-alias) are needed for the resolved package version, and add them here too if so.

- [x] **Step 4: Write the failing test**

Create `mobile/test/features/biofeedback/biofeedback_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';

void main() {
  test('round-trips through toJson and fromJson with all fields present', () {
    final original = BiofeedbackSummary(
      ultimaFc: 72.0,
      mediaFcHoje: 68.5,
      mediaVfcHoje: 45.2,
      atualizadoEm: DateTime.utc(2026, 8, 3, 14, 30),
    );

    final roundTripped = BiofeedbackSummary.fromJson(original.toJson());

    expect(roundTripped.ultimaFc, 72.0);
    expect(roundTripped.mediaFcHoje, 68.5);
    expect(roundTripped.mediaVfcHoje, 45.2);
    expect(roundTripped.atualizadoEm, DateTime.utc(2026, 8, 3, 14, 30));
  });

  test('round-trips with null fields (no readings yet)', () {
    final original = BiofeedbackSummary(
      ultimaFc: null,
      mediaFcHoje: null,
      mediaVfcHoje: null,
      atualizadoEm: DateTime.utc(2026, 8, 3, 9, 0),
    );

    final roundTripped = BiofeedbackSummary.fromJson(original.toJson());

    expect(roundTripped.ultimaFc, isNull);
    expect(roundTripped.mediaFcHoje, isNull);
    expect(roundTripped.mediaVfcHoje, isNull);
  });
}
```

- [x] **Step 5: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_summary_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'sincro_mobile/features/biofeedback/biofeedback_summary.dart'`

- [x] **Step 6: Write the model files**

Create `mobile/lib/features/biofeedback/health_reading.dart`:

```dart
class HealthReading {
  const HealthReading({required this.valor, required this.timestamp});

  final double valor;
  final DateTime timestamp;
}
```

Create `mobile/lib/features/biofeedback/biofeedback_summary.dart`:

```dart
class BiofeedbackSummary {
  const BiofeedbackSummary({
    required this.ultimaFc,
    required this.mediaFcHoje,
    required this.mediaVfcHoje,
    required this.atualizadoEm,
  });

  final double? ultimaFc;
  final double? mediaFcHoje;
  final double? mediaVfcHoje;
  final DateTime atualizadoEm;

  Map<String, dynamic> toJson() => {
        'ultimaFc': ultimaFc,
        'mediaFcHoje': mediaFcHoje,
        'mediaVfcHoje': mediaVfcHoje,
        'atualizadoEm': atualizadoEm.toIso8601String(),
      };

  factory BiofeedbackSummary.fromJson(Map<String, dynamic> json) {
    return BiofeedbackSummary(
      ultimaFc: (json['ultimaFc'] as num?)?.toDouble(),
      mediaFcHoje: (json['mediaFcHoje'] as num?)?.toDouble(),
      mediaVfcHoje: (json['mediaVfcHoje'] as num?)?.toDouble(),
      atualizadoEm: DateTime.parse(json['atualizadoEm'] as String),
    );
  }
}
```

Create `mobile/lib/features/biofeedback/biofeedback_frequencia.dart`:

```dart
enum BiofeedbackFrequencia {
  quinzeMinutos(Duration(minutes: 15), '15 minutos'),
  trintaMinutos(Duration(minutes: 30), '30 minutos'),
  umaHora(Duration(hours: 1), '1 hora'),
  duasHoras(Duration(hours: 2), '2 horas');

  const BiofeedbackFrequencia(this.duracao, this.label);

  final Duration duracao;
  final String label;
}
```

- [x] **Step 7: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_summary_test.dart`
Expected: PASS (2 tests)

- [x] **Step 8: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock mobile/ios/Runner/Info.plist mobile/android/app/src/main/AndroidManifest.xml mobile/lib/features/biofeedback mobile/test/features/biofeedback
git commit -m "feat: add health/workmanager/shared_preferences deps and biofeedback models"
```

---

## Task 2: Biofeedback summary calculator

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_summary_calculator.dart`
- Test: `mobile/test/features/biofeedback/biofeedback_summary_calculator_test.dart`

**Interfaces:**
- Consumes: `HealthReading`, `BiofeedbackSummary` (Task 1).
- Produces: `BiofeedbackSummaryCalculator.calcular({required List<HealthReading> leiturasFc, required List<HealthReading> leiturasVfc, required DateTime agora}): BiofeedbackSummary`. Consumed by Task 5 (sync service).

- [x] **Step 1: Write the failing test**

Create `mobile/test/features/biofeedback/biofeedback_summary_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary_calculator.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';

void main() {
  final calculator = BiofeedbackSummaryCalculator();
  final agora = DateTime(2026, 8, 3, 15, 0);

  test('returns all-null summary when there are no readings at all', () {
    final resumo = calculator.calcular(leiturasFc: [], leiturasVfc: [], agora: agora);

    expect(resumo.ultimaFc, isNull);
    expect(resumo.mediaFcHoje, isNull);
    expect(resumo.mediaVfcHoje, isNull);
    expect(resumo.atualizadoEm, agora);
  });

  test('a single FC reading is both the latest value and the average', () {
    final resumo = calculator.calcular(
      leiturasFc: [HealthReading(valor: 80, timestamp: DateTime(2026, 8, 3, 9, 0))],
      leiturasVfc: [],
      agora: agora,
    );

    expect(resumo.ultimaFc, 80);
    expect(resumo.mediaFcHoje, 80);
    expect(resumo.mediaVfcHoje, isNull);
  });

  test('averages multiple readings and picks the most recent as the latest value', () {
    final resumo = calculator.calcular(
      leiturasFc: [
        HealthReading(valor: 70, timestamp: DateTime(2026, 8, 3, 8, 0)),
        HealthReading(valor: 90, timestamp: DateTime(2026, 8, 3, 12, 0)),
        HealthReading(valor: 80, timestamp: DateTime(2026, 8, 3, 14, 30)),
      ],
      leiturasVfc: [
        HealthReading(valor: 40, timestamp: DateTime(2026, 8, 3, 8, 0)),
        HealthReading(valor: 50, timestamp: DateTime(2026, 8, 3, 14, 0)),
      ],
      agora: agora,
    );

    expect(resumo.mediaFcHoje, closeTo(80, 0.001)); // (70+90+80)/3
    expect(resumo.mediaVfcHoje, 45); // (40+50)/2
    // Última FC é a de 14:30 (mais recente por timestamp), não a última da lista por ordem de inserção.
    expect(resumo.ultimaFc, 80);
  });

  test('picks the most recent reading by timestamp even when it is not last in the list', () {
    final resumo = calculator.calcular(
      leiturasFc: [
        HealthReading(valor: 100, timestamp: DateTime(2026, 8, 3, 14, 0)), // mais recente, primeiro na lista
        HealthReading(valor: 60, timestamp: DateTime(2026, 8, 3, 7, 0)),
      ],
      leiturasVfc: [],
      agora: agora,
    );

    expect(resumo.ultimaFc, 100);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_summary_calculator_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package '.../biofeedback_summary_calculator.dart'`

- [x] **Step 3: Write minimal implementation**

Create `mobile/lib/features/biofeedback/biofeedback_summary_calculator.dart`:

```dart
import 'biofeedback_summary.dart';
import 'health_reading.dart';

class BiofeedbackSummaryCalculator {
  BiofeedbackSummary calcular({
    required List<HealthReading> leiturasFc,
    required List<HealthReading> leiturasVfc,
    required DateTime agora,
  }) {
    return BiofeedbackSummary(
      ultimaFc: _ultimoValor(leiturasFc),
      mediaFcHoje: _media(leiturasFc),
      mediaVfcHoje: _media(leiturasVfc),
      atualizadoEm: agora,
    );
  }

  double? _ultimoValor(List<HealthReading> leituras) {
    if (leituras.isEmpty) return null;
    final maisRecente = leituras.reduce(
      (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
    );
    return maisRecente.valor;
  }

  double? _media(List<HealthReading> leituras) {
    if (leituras.isEmpty) return null;
    final soma = leituras.fold<double>(0, (total, r) => total + r.valor);
    return soma / leituras.length;
  }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_summary_calculator_test.dart`
Expected: PASS (4 tests)

- [x] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_summary_calculator.dart mobile/test/features/biofeedback/biofeedback_summary_calculator_test.dart
git commit -m "feat: add pure biofeedback summary calculator"
```

---

## Task 3: Local cache

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_cache.dart`
- Test: `mobile/test/features/biofeedback/biofeedback_cache_test.dart`

**Interfaces:**
- Consumes: `BiofeedbackSummary` (Task 1).
- Produces: `BiofeedbackCache` with `isAtivo(): Future<bool>`, `setAtivo(bool): Future<void>`, `getFrequenciaMinutos(): Future<int>` (default 30), `setFrequenciaMinutos(int): Future<void>`, `getResumo(): Future<BiofeedbackSummary?>`, `setResumo(BiofeedbackSummary): Future<void>`, `clear(): Future<void>`. Consumed by Tasks 5, 7, 8, 9, 10.

- [x] **Step 1: Write the failing test**

Create `mobile/test/features/biofeedback/biofeedback_cache_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_cache.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('isAtivo defaults to false when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    expect(await cache.isAtivo(), false);
  });

  test('setAtivo persists the flag for later reads', () async {
    final cache = BiofeedbackCache();

    await cache.setAtivo(true);

    expect(await cache.isAtivo(), true);
  });

  test('getFrequenciaMinutos defaults to 30 when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    expect(await cache.getFrequenciaMinutos(), 30);
  });

  test('setFrequenciaMinutos persists the chosen value', () async {
    final cache = BiofeedbackCache();

    await cache.setFrequenciaMinutos(60);

    expect(await cache.getFrequenciaMinutos(), 60);
  });

  test('getResumo returns null when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    expect(await cache.getResumo(), isNull);
  });

  test('setResumo then getResumo round-trips the summary', () async {
    final cache = BiofeedbackCache();
    final resumo = BiofeedbackSummary(
      ultimaFc: 72,
      mediaFcHoje: 70,
      mediaVfcHoje: 45,
      atualizadoEm: DateTime.utc(2026, 8, 3, 14, 0),
    );

    await cache.setResumo(resumo);
    final lido = await cache.getResumo();

    expect(lido?.ultimaFc, 72);
    expect(lido?.atualizadoEm, DateTime.utc(2026, 8, 3, 14, 0));
  });

  test('clear removes ativo, frequencia, and resumo together', () async {
    final cache = BiofeedbackCache();
    await cache.setAtivo(true);
    await cache.setFrequenciaMinutos(60);
    await cache.setResumo(BiofeedbackSummary(
      ultimaFc: 72,
      mediaFcHoje: 70,
      mediaVfcHoje: 45,
      atualizadoEm: DateTime.utc(2026, 8, 3, 14, 0),
    ));

    await cache.clear();

    expect(await cache.isAtivo(), false);
    expect(await cache.getFrequenciaMinutos(), 30);
    expect(await cache.getResumo(), isNull);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_cache_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package '.../biofeedback_cache.dart'`

- [x] **Step 3: Write minimal implementation**

Create `mobile/lib/features/biofeedback/biofeedback_cache.dart`:

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'biofeedback_summary.dart';

const _chaveAtivo = 'biofeedback_ativo';
const _chaveFrequenciaMinutos = 'biofeedback_frequencia_minutos';
const _chaveResumo = 'biofeedback_resumo';
const _frequenciaPadraoMinutos = 30;

class BiofeedbackCache {
  Future<bool> isAtivo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chaveAtivo) ?? false;
  }

  Future<void> setAtivo(bool ativo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveAtivo, ativo);
  }

  Future<int> getFrequenciaMinutos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_chaveFrequenciaMinutos) ?? _frequenciaPadraoMinutos;
  }

  Future<void> setFrequenciaMinutos(int minutos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chaveFrequenciaMinutos, minutos);
  }

  Future<BiofeedbackSummary?> getResumo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chaveResumo);
    if (raw == null) return null;
    return BiofeedbackSummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setResumo(BiofeedbackSummary resumo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveResumo, jsonEncode(resumo.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveAtivo);
    await prefs.remove(_chaveFrequenciaMinutos);
    await prefs.remove(_chaveResumo);
  }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_cache_test.dart`
Expected: PASS (7 tests)

- [x] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_cache.dart mobile/test/features/biofeedback/biofeedback_cache_test.dart
git commit -m "feat: add local shared_preferences cache for biofeedback summary"
```

---

## Task 4: Health data source (HealthKit/Health Connect wrapper)

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_health_service.dart`

**Interfaces:**
- Consumes: `HealthReading` (Task 1); the `health` package (Task 1's dependency).
- Produces: `BiofeedbackHealthService` with `solicitarPermissao(): Future<bool>`, `lerFrequenciaCardiacaHoje(): Future<List<HealthReading>>`, `lerVariabilidadeHoje(): Future<List<HealthReading>>`. Consumed by Task 5 (and mocked there via `mocktail`, the same way this codebase already mocks concrete classes like `GoogleSignIn` — no separate abstract interface needed).

This file wraps a package that talks to native platform code — it has no automated test in this plan (there's no platform channel available under `flutter test`). Verification here is `flutter analyze` plus the manual device check called out in the spec's Testes section.

- [x] **Step 1: Write the implementation**

Per Prerequisite 1, confirm the `health` package's actual API against what's resolved in `mobile/pubspec.lock` before treating this as final — adjust method/type names if they differ.

Create `mobile/lib/features/biofeedback/biofeedback_health_service.dart`:

```dart
import 'package:health/health.dart';
import 'health_reading.dart';

class BiofeedbackHealthService {
  final Health _health = Health();

  static const _tipos = [
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  ];

  Future<bool> solicitarPermissao() async {
    return _health.requestAuthorization(
      _tipos,
      permissions: _tipos.map((_) => HealthDataAccess.READ).toList(),
    );
  }

  Future<List<HealthReading>> lerFrequenciaCardiacaHoje() {
    return _lerTipoHoje(HealthDataType.HEART_RATE);
  }

  Future<List<HealthReading>> lerVariabilidadeHoje() {
    return _lerTipoHoje(HealthDataType.HEART_RATE_VARIABILITY_SDNN);
  }

  Future<List<HealthReading>> _lerTipoHoje(HealthDataType tipo) async {
    final agora = DateTime.now();
    final inicioDoDia = DateTime(agora.year, agora.month, agora.day);
    final pontos = await _health.getHealthDataFromTypes(
      types: [tipo],
      startTime: inicioDoDia,
      endTime: agora,
    );
    return pontos
        .map(
          (p) => HealthReading(
            valor: (p.value as NumericHealthValue).numericValue.toDouble(),
            timestamp: p.dateFrom,
          ),
        )
        .toList();
  }
}
```

- [x] **Step 2: Verify it compiles**

Run: `cd mobile && flutter analyze lib/features/biofeedback/biofeedback_health_service.dart`
Expected: "No issues found!" — if the `health` package's actual API differs from what's used above (per Prerequisite 1), fix the mismatches here until this is clean.

- [x] **Step 3: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_health_service.dart
git commit -m "feat: add HealthKit/Health Connect data source wrapper"
```

---

## Task 5: Sync service

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_sync_service.dart`
- Test: `mobile/test/features/biofeedback/biofeedback_sync_service_test.dart`

**Interfaces:**
- Consumes: `BiofeedbackHealthService.lerFrequenciaCardiacaHoje()`/`lerVariabilidadeHoje()` (Task 4); `BiofeedbackCache.setResumo()` (Task 3); `BiofeedbackSummaryCalculator.calcular()` (Task 2).
- Produces: `BiofeedbackSyncService(BiofeedbackHealthService, BiofeedbackCache, BiofeedbackSummaryCalculator)` with `sincronizar({DateTime? agora}): Future<void>`. Consumed by Task 6 (background callback), Task 7 (provider), Task 8 (Home card activation), Task 9 (pull-to-refresh).

- [x] **Step 1: Write the failing test**

Create `mobile/test/features/biofeedback/biofeedback_sync_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_cache.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_health_service.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary_calculator.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_sync_service.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';

class MockBiofeedbackHealthService extends Mock implements BiofeedbackHealthService {}

class MockBiofeedbackCache extends Mock implements BiofeedbackCache {}

class FakeBiofeedbackSummary extends Fake implements BiofeedbackSummary {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeBiofeedbackSummary());
  });

  test('reads FC and VFC, computes the summary, and saves it to the cache', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 80, timestamp: DateTime(2026, 8, 3, 9, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 45, timestamp: DateTime(2026, 8, 3, 9, 0))],
    );
    when(() => cache.setResumo(any())).thenAnswer((_) async {});
    final service = BiofeedbackSyncService(healthService, cache, BiofeedbackSummaryCalculator());

    await service.sincronizar(agora: agora);

    final captured = verify(() => cache.setResumo(captureAny())).captured;
    final salvo = captured.single as BiofeedbackSummary;
    expect(salvo.ultimaFc, 80);
    expect(salvo.mediaFcHoje, 80);
    expect(salvo.mediaVfcHoje, 45);
    expect(salvo.atualizadoEm, agora);
  });

  test('saves an all-null summary when there are no readings yet', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer((_) async => []);
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer((_) async => []);
    when(() => cache.setResumo(any())).thenAnswer((_) async {});
    final service = BiofeedbackSyncService(healthService, cache, BiofeedbackSummaryCalculator());

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    final captured = verify(() => cache.setResumo(captureAny())).captured;
    final salvo = captured.single as BiofeedbackSummary;
    expect(salvo.ultimaFc, isNull);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_sync_service_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package '.../biofeedback_sync_service.dart'`

- [x] **Step 3: Write minimal implementation**

Create `mobile/lib/features/biofeedback/biofeedback_sync_service.dart`:

```dart
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_summary_calculator.dart';

class BiofeedbackSyncService {
  BiofeedbackSyncService(this._healthService, this._cache, this._calculator);

  final BiofeedbackHealthService _healthService;
  final BiofeedbackCache _cache;
  final BiofeedbackSummaryCalculator _calculator;

  Future<void> sincronizar({DateTime? agora}) async {
    final leiturasFc = await _healthService.lerFrequenciaCardiacaHoje();
    final leiturasVfc = await _healthService.lerVariabilidadeHoje();
    final resumo = _calculator.calcular(
      leiturasFc: leiturasFc,
      leiturasVfc: leiturasVfc,
      agora: agora ?? DateTime.now(),
    );
    await _cache.setResumo(resumo);
  }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_sync_service_test.dart`
Expected: PASS (2 tests)

- [x] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_sync_service.dart mobile/test/features/biofeedback/biofeedback_sync_service_test.dart
git commit -m "feat: add biofeedback sync service (health -> calculator -> cache)"
```

---

## Task 6: Background task scheduling

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_background_task.dart`
- Modify: `mobile/lib/main.dart`

**Interfaces:**
- Consumes: `BiofeedbackSyncService`, `BiofeedbackHealthService`, `BiofeedbackCache`, `BiofeedbackSummaryCalculator` (Tasks 2-5); the `workmanager` package (Task 1's dependency).
- Produces: `BiofeedbackBackgroundTask` with `registrar(Duration): Future<void>`, `cancelar(): Future<void>`; top-level `biofeedbackCallbackDispatcher()` function. Consumed by Task 7 (provider), Task 8 (activation), Task 10 (frequency change/deactivation).

No automated test — `workmanager` needs platform channels unavailable under `flutter test`, same situation as Task 4. Verified via `flutter analyze` plus the manual device check.

- [ ] **Step 1: Write the implementation**

Per Prerequisite 2, confirm `workmanager`'s actual API against what's resolved in `mobile/pubspec.lock` before treating this as final.

Create `mobile/lib/features/biofeedback/biofeedback_background_task.dart`:

```dart
import 'package:workmanager/workmanager.dart';
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_summary_calculator.dart';
import 'biofeedback_sync_service.dart';

const biofeedbackTaskName = 'biofeedback-sync';

/// Roda em um isolate separado do app principal — não tem acesso ao ProviderScope do Riverpod,
/// então monta suas próprias instâncias das mesmas classes usadas em primeiro plano.
@pragma('vm:entry-point')
void biofeedbackCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != biofeedbackTaskName) return true;
    final syncService = BiofeedbackSyncService(
      BiofeedbackHealthService(),
      BiofeedbackCache(),
      BiofeedbackSummaryCalculator(),
    );
    try {
      await syncService.sincronizar();
    } catch (_) {
      // Sincronização em background é best-effort: uma falha aqui não deve impedir
      // que o workmanager continue agendando as próximas execuções.
    }
    return true;
  });
}

class BiofeedbackBackgroundTask {
  Future<void> registrar(Duration frequencia) async {
    // Cancela antes de registrar de novo: troca de frequência precisa substituir o
    // agendamento anterior, não empilhar um segundo em paralelo.
    await Workmanager().cancelByUniqueName(biofeedbackTaskName);
    await Workmanager().registerPeriodicTask(
      biofeedbackTaskName,
      biofeedbackTaskName,
      frequency: frequencia,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  Future<void> cancelar() async {
    await Workmanager().cancelByUniqueName(biofeedbackTaskName);
  }
}
```

Update `mobile/lib/main.dart`:
- Add the import `import 'features/biofeedback/biofeedback_background_task.dart';`.
- Inside `main()`, after `await Firebase.initializeApp(...)` and before `runApp(...)`, add:

```dart
  Workmanager().initialize(biofeedbackCallbackDispatcher);
```

(This also needs `import 'package:workmanager/workmanager.dart';` added to `main.dart`.)

- [ ] **Step 2: Verify it compiles**

Run: `cd mobile && flutter analyze`
Expected: "No issues found!" — if `workmanager`'s actual API differs from what's used above (per Prerequisite 2), fix the mismatches until this is clean.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_background_task.dart mobile/lib/main.dart
git commit -m "feat: add workmanager-scheduled background biofeedback sync"
```

---

## Task 7: Riverpod providers

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_providers.dart`

**Interfaces:**
- Consumes: `BiofeedbackHealthService`, `BiofeedbackCache`, `BiofeedbackSyncService`, `BiofeedbackBackgroundTask`, `BiofeedbackSummaryCalculator` (Tasks 2-6).
- Produces: `biofeedbackHealthServiceProvider`, `biofeedbackCacheProvider`, `biofeedbackSyncServiceProvider`, `biofeedbackBackgroundTaskProvider` (all plain `Provider`); `biofeedbackAtivoProvider` (`FutureProvider.autoDispose<bool>`), `biofeedbackResumoProvider` (`FutureProvider.autoDispose<BiofeedbackSummary?>`), `biofeedbackFrequenciaProvider` (`FutureProvider.autoDispose<int>`). Consumed by Tasks 8, 9, 10.

No test for this file — it's pure dependency wiring with no logic of its own, consistent with how `finance_providers.dart`/`email_triage_providers.dart` aren't unit-tested elsewhere in this codebase.

- [ ] **Step 1: Write the implementation**

Create `mobile/lib/features/biofeedback/biofeedback_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'biofeedback_background_task.dart';
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_summary.dart';
import 'biofeedback_summary_calculator.dart';
import 'biofeedback_sync_service.dart';

final biofeedbackHealthServiceProvider = Provider<BiofeedbackHealthService>((ref) {
  return BiofeedbackHealthService();
});

final biofeedbackCacheProvider = Provider<BiofeedbackCache>((ref) {
  return BiofeedbackCache();
});

final biofeedbackSyncServiceProvider = Provider<BiofeedbackSyncService>((ref) {
  return BiofeedbackSyncService(
    ref.watch(biofeedbackHealthServiceProvider),
    ref.watch(biofeedbackCacheProvider),
    BiofeedbackSummaryCalculator(),
  );
});

final biofeedbackBackgroundTaskProvider = Provider<BiofeedbackBackgroundTask>((ref) {
  return BiofeedbackBackgroundTask();
});

final biofeedbackAtivoProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(biofeedbackCacheProvider).isAtivo();
});

final biofeedbackResumoProvider = FutureProvider.autoDispose<BiofeedbackSummary?>((ref) {
  return ref.watch(biofeedbackCacheProvider).getResumo();
});

final biofeedbackFrequenciaProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(biofeedbackCacheProvider).getFrequenciaMinutos();
});
```

- [ ] **Step 2: Verify it compiles**

Run: `cd mobile && flutter analyze lib/features/biofeedback/biofeedback_providers.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_providers.dart
git commit -m "feat: add biofeedback Riverpod providers"
```

---

## Task 8: Home card and activation flow

**Files:**
- Modify: `mobile/lib/features/home/home_screen.dart`

**Interfaces:**
- Consumes: `biofeedbackAtivoProvider`, `biofeedbackResumoProvider`, `biofeedbackHealthServiceProvider`, `biofeedbackSyncServiceProvider`, `biofeedbackCacheProvider`, `biofeedbackBackgroundTaskProvider` (Task 7).

No automated test — this widget's only non-trivial logic is the activation flow, which calls through to the untested `health`/`workmanager` wrappers; verified via `flutter analyze` and the manual device check, consistent with how `_FinancasCard`'s Pluggy Connect flow was handled.

- [ ] **Step 1: Add the import**

In `mobile/lib/features/home/home_screen.dart`, add:

```dart
import '../biofeedback/biofeedback_providers.dart';
```

- [ ] **Step 2: Watch the activation state in `_HomeScreenState.build`**

Add this line alongside the existing `final financeConnectionsAsync = ...;` line:

```dart
    final biofeedbackAtivoAsync = ref.watch(biofeedbackAtivoProvider);
```

Then change this exact block in the `Column`'s `children`:

```dart
            _FinancasCard(connectionsAsync: financeConnectionsAsync),
            const SizedBox(height: 16),
            contactsAsync.when(
```

to:

```dart
            _FinancasCard(connectionsAsync: financeConnectionsAsync),
            const SizedBox(height: 16),
            _BiofeedbackCard(ativoAsync: biofeedbackAtivoAsync),
            const SizedBox(height: 16),
            contactsAsync.when(
```

(card order becomes: Gmail → Finanças → Biofeedback → the rest of the column, unchanged).

- [ ] **Step 3: Add the `_BiofeedbackCard` and `_UltimaFcSubtitle` widgets**

Add these two new classes at the end of `home_screen.dart` (after the existing `_SaldoLivreSubtitle` class, before `_NoContactsHint`):

```dart
class _BiofeedbackCard extends ConsumerWidget {
  const _BiofeedbackCard({required this.ativoAsync});

  final AsyncValue<bool> ativoAsync;

  Future<void> _ativar(BuildContext context, WidgetRef ref) async {
    try {
      final autorizado = await ref.read(biofeedbackHealthServiceProvider).solicitarPermissao();
      if (!autorizado) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissão não concedida. Você pode tentar novamente quando quiser.'),
            ),
          );
        }
        return;
      }
      await ref.read(biofeedbackSyncServiceProvider).sincronizar();
      await ref.read(biofeedbackCacheProvider).setAtivo(true);
      final frequenciaMinutos = await ref.read(biofeedbackCacheProvider).getFrequenciaMinutos();
      await ref.read(biofeedbackBackgroundTaskProvider).registrar(Duration(minutes: frequenciaMinutos));
      ref.invalidate(biofeedbackAtivoProvider);
      ref.invalidate(biofeedbackResumoProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível ativar o Biofeedback. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ativoAsync.when(
      data: (ativo) {
        if (!ativo) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('💓 Biofeedback'),
              subtitle: const Text('Acompanhe seu bem-estar com seu smartwatch.'),
              trailing: ElevatedButton(
                onPressed: () => _ativar(context, ref),
                child: const Text('Ativar Biofeedback'),
              ),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('💓 Biofeedback'),
            subtitle: const _UltimaFcSubtitle(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/biofeedback'),
          ),
        );
      },
      loading: () => const Card(child: ListTile(title: Text('💓 Biofeedback'), subtitle: Text('Carregando...'))),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Mostrada só quando o Biofeedback já está ativo (ver `_BiofeedbackCard.build`), então "nenhum
/// dado disponível ainda" aqui significa "ativado mas sem smartwatch pareado", não "não ativado".
class _UltimaFcSubtitle extends ConsumerWidget {
  const _UltimaFcSubtitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumoAsync = ref.watch(biofeedbackResumoProvider);
    return resumoAsync.when(
      data: (resumo) {
        if (resumo?.ultimaFc == null) return const Text('Nenhum dado disponível ainda');
        return Text('${resumo!.ultimaFc!.round()} bpm agora');
      },
      loading: () => const Text('Carregando...'),
      error: (_, __) => const Text('Nenhum dado disponível ainda'),
    );
  }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `cd mobile && flutter analyze lib/features/home/home_screen.dart`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/home/home_screen.dart
git commit -m "feat: add Biofeedback Home card and activation flow"
```

---

## Task 9: Detail screen

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_screen.dart`
- Modify: `mobile/lib/main.dart`

**Interfaces:**
- Consumes: `biofeedbackResumoProvider`, `biofeedbackSyncServiceProvider` (Task 7); `BiofeedbackSummary` (Task 1).
- Produces: `BiofeedbackScreen` widget; `/biofeedback` route.

No automated test — same reasoning as `financas_screen.dart`/`inbox_screen.dart`, this codebase doesn't widget-test its detail screens; verified via `flutter analyze` and manual run.

- [ ] **Step 1: Write the implementation**

Create `mobile/lib/features/biofeedback/biofeedback_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'biofeedback_providers.dart';
import 'biofeedback_summary.dart';

class BiofeedbackScreen extends ConsumerWidget {
  const BiofeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumoAsync = ref.watch(biofeedbackResumoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Biofeedback')),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(biofeedbackSyncServiceProvider).sincronizar();
          } catch (_) {
            // Sincronização sob demanda é best-effort: se falhar, ainda mostramos os dados em cache.
          }
          ref.invalidate(biofeedbackResumoProvider);
        },
        child: resumoAsync.when(
          data: (resumo) => _BiofeedbackContent(resumo: resumo),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('Não foi possível carregar seus dados. Puxe para tentar novamente.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BiofeedbackContent extends StatelessWidget {
  const _BiofeedbackContent({required this.resumo});

  final BiofeedbackSummary? resumo;

  @override
  Widget build(BuildContext context) {
    final atual = resumo;
    if (atual == null) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum dado disponível ainda. 🌿'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Frequência cardíaca média hoje', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  atual.mediaFcHoje != null ? '${atual.mediaFcHoje!.round()} bpm' : '—',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Variabilidade média hoje', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  atual.mediaVfcHoje != null ? '${atual.mediaVfcHoje!.round()} ms' : '—',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Atualizado às ${TimeOfDay.fromDateTime(atual.atualizadoEm).format(context)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
```

Update `mobile/lib/main.dart`:
- Add the import `import 'features/biofeedback/biofeedback_screen.dart';`.
- Add `'/biofeedback': (_) => const BiofeedbackScreen(),` to the `routes` map, after `'/financas'`.

- [ ] **Step 2: Verify it compiles**

Run: `cd mobile && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_screen.dart mobile/lib/main.dart
git commit -m "feat: add biofeedback detail screen with pull-to-refresh"
```

---

## Task 10: Settings — frequency selector and deactivation

**Files:**
- Modify: `mobile/lib/features/settings/settings_screen.dart`

**Interfaces:**
- Consumes: `biofeedbackCacheProvider`, `biofeedbackBackgroundTaskProvider`, `biofeedbackAtivoProvider` (Task 7); `BiofeedbackFrequencia` (Task 1).

No automated test — same reasoning as the `dia_recebimento` dialog, this codebase doesn't widget-test its Settings dialogs; verified via `flutter analyze` and manual run.

- [ ] **Step 1: Add imports**

In `mobile/lib/features/settings/settings_screen.dart`, add:

```dart
import '../biofeedback/biofeedback_frequencia.dart';
import '../biofeedback/biofeedback_providers.dart';
```

- [ ] **Step 2: Add the two new methods**

Add these inside `_SettingsScreenState`, alongside the existing `_editDiaRecebimento`/`_disconnectFinanceConnection` methods:

```dart
  Future<void> _editBiofeedbackFrequencia() async {
    final atual = await ref.read(biofeedbackCacheProvider).getFrequenciaMinutos();
    if (!mounted) return;

    final escolhida = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Frequência de atualização'),
        children: BiofeedbackFrequencia.values.map((f) {
          return RadioListTile<int>(
            title: Text(f.label),
            value: f.duracao.inMinutes,
            groupValue: atual,
            onChanged: (v) => Navigator.pop(dialogContext, v),
          );
        }).toList(),
      ),
    );
    if (escolhida == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(biofeedbackCacheProvider).setFrequenciaMinutos(escolhida);
      final ativo = await ref.read(biofeedbackCacheProvider).isAtivo();
      if (ativo) {
        await ref.read(biofeedbackBackgroundTaskProvider).registrar(Duration(minutes: escolhida));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Frequência atualizada.')),
        );
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

  Future<void> _desativarBiofeedback() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desativar Biofeedback?'),
        content: const Text(
          'Os dados de frequência cardíaca guardados no app serão apagados. '
          'Você pode ativar novamente quando quiser.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desativar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(biofeedbackBackgroundTaskProvider).cancelar();
      await ref.read(biofeedbackCacheProvider).clear();
      ref.invalidate(biofeedbackAtivoProvider);
      ref.invalidate(biofeedbackResumoProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Biofeedback desativado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível desativar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

- [ ] **Step 3: Wire the new tiles into `build()`**

In `build()`, add this alongside the existing `final connectionsAsync = ref.watch(financeConnectionsProvider);` line:

```dart
    final biofeedbackAtivo = ref.watch(biofeedbackAtivoProvider).maybeWhen(
          data: (ativo) => ativo,
          orElse: () => false,
        );
```

Then add these two `ListTile`s to the `ListView`'s `children`, right after the existing `...financeConnectionTiles,` line and before the `const Divider(),`:

```dart
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('Frequência do Biofeedback'),
            onTap: _busy ? null : _editBiofeedbackFrequencia,
          ),
          if (biofeedbackAtivo)
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Desativar Biofeedback'),
              onTap: _busy ? null : _desativarBiofeedback,
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
git commit -m "feat: add biofeedback frequency setting and deactivation"
```

---

## Plan Self-Review Notes

**Spec coverage:**
- Ativar via card na Home + permissão HealthKit/Health Connect → Task 8.
- Card mostra FC mais recente; tela de detalhe mostra médias do dia de FC/VFC → Tasks 8, 9.
- Frequência de atualização em background (15/30/60/120 min), editável a qualquer momento → Tasks 1 (enum), 10 (UI), 6/8 (aplicação no `workmanager`).
- Desativar apaga cache local e cancela a tarefa em background → Task 10, backed by `BiofeedbackCache.clear()` (Task 3) and `BiofeedbackBackgroundTask.cancelar()` (Task 6).
- Nenhum dado toca o backend → nenhuma task neste plano toca `backend/`; confirmado por grep mental — não há nenhuma referência a `Dio`/HTTP em nenhum arquivo deste módulo.
- Estado "sem dados"/permissão negada não bloqueia o resto do app → Task 8's `_ativar` catches and shows a snackbar without throwing further; card always renders regardless of state.

**Placeholder scan:** No TBD/TODO. The two platform-integration tasks (4, 6) have no automated test by design (documented in the spec itself), not because of a missing decision — each still has concrete, complete code and a concrete verification step (`flutter analyze` + the spec's manual-verification note).

**Type consistency:** `HealthReading`, `BiofeedbackSummary`, `BiofeedbackFrequencia` (Task 1) are used with identical field names across every later task (`valor`/`timestamp`; `ultimaFc`/`mediaFcHoje`/`mediaVfcHoje`/`atualizadoEm`; `.duracao`/`.label`). `BiofeedbackCache`'s method names (`isAtivo`, `setAtivo`, `getFrequenciaMinutos`, `setFrequenciaMinutos`, `getResumo`, `setResumo`, `clear`) match exactly between Task 3's implementation and every consumer (Tasks 5, 7, 8, 10). `BiofeedbackSyncService.sincronizar` and `BiofeedbackBackgroundTask.registrar`/`cancelar` are likewise consistent everywhere they're called.

**Deferred (explicitly out of scope, from the approved spec):**
- Detecção de estresse e filtragem de falsos positivos por atividade física (Fase 2 deste pilar).
- Alertas de descompressão / intervenção (Fase 3 deste pilar).
- Persistência no backend, incluindo qualquer coisa que alimente `perfis_sensoriais` com limiares de estresse (Fase 2/3).
- `enableBackgroundDelivery` do HealthKit (mais responsivo que polling, mas só compensa quando houver alerta para disparar).
