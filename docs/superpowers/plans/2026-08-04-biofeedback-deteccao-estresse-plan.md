# Biofeedback & Crise — Detecção de Estresse (Fase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compare recent heart-rate/HRV readings (filtered to exclude physical-activity periods) against a personal, automatically-built baseline, and surface a calm "Calmo" / "Elevado" / "Coletando dados" state on the Home card and the Biofeedback detail screen — no alerts, no backend, still 100% on-device.

**Architecture:** Extends the existing `mobile/lib/features/biofeedback/` module from Fase 1 (already merged into `master`). Adds a pure `BiofeedbackStressDetector` (same style as the existing `BiofeedbackSummaryCalculator`) that filters readings by physical activity, maintains a 14-day rolling window of daily resting-average entries in the existing `BiofeedbackCache`, and derives a stress state by comparing today's resting average against that window's mean/standard-deviation. `BiofeedbackHealthService` gains two new read methods (`STEPS`, `WORKOUT`) reused by the detector's activity filter. `BiofeedbackSyncService` orchestrates all of it in the same background/foreground sync cycle Fase 1 already runs.

**Tech Stack:** Same as Fase 1 — Flutter + Riverpod, the `health` package (already a dependency, now reading two more `HealthDataType`s), `shared_preferences` (`SharedPreferencesAsync`, already the cache's backend since Fase 1's fix-wave). No new packages.

## Global Constraints

- No FC/VFC/passos/treino data touches the network or the backend — everything stays on-device, same as Fase 1. This phase makes zero backend changes.
- The detection window compares **médias do período** (daily resting averages), never single instantaneous readings.
- A reading at instant `t` counts as **"em repouso"** only if: no `WORKOUT` interval covers `t`, **and** total steps in the 5-minute window centered on `t` (`t - 2m30s` to `t + 2m30s`) is strictly less than 15.
- The rolling history window holds at most **14 days** of `{data, mediaFcRepouso, mediaVfcRepouso}` entries; the day being evaluated is always excluded from its own baseline.
- The baseline is only "ready" once the window has **at least 7 days** of history excluding today. Before that, the state is `coletandoDados`.
- State is `elevado` only when **both** conditions hold together: today's resting FC average `>= baseline mean + 1.5 * baseline stddev`, **and** today's resting VFC average `<= baseline mean - 1.5 * baseline stddev`. Either condition alone is not enough.
- If a baseline standard deviation is `0`, that metric's condition can never trigger `elevado` (avoids false positives from a degenerate baseline with no real variance).
- No color-coding, no charts, no graded severity — only the three states `calmo` / `elevado` / `coletandoDados`, shown as plain text, same calm tone as the rest of the app.
- Thresholds (14-day window, 7-day minimum, 15-step limiar, 1.5 standard deviations) are fixed in code this phase — not user-configurable.
- Deactivating Biofeedback (`BiofeedbackCache.clear()`) must also erase the resting history — no FC/VFC/passos/treino-derived data survives deactivation.

---

## Prerequisites

Unlike Fase 1, the two new `health` package permission strings below are already confirmed against the resolved `health-13.3.1` source in this checkout (not just the README) — no open question to resolve mid-task:

1. Android: `android.permission.health.READ_STEPS` and `android.permission.health.READ_EXERCISE` (confirmed against `health-13.3.1/example/android/app/src/main/AndroidManifest.xml` — `WORKOUT` in the `health` package's Dart API maps to Health Connect's `EXERCISE` permission). Both `HealthDataType.STEPS` and `HealthDataType.WORKOUT` are confirmed present in `health-13.3.1`'s `dataTypeKeysIOS` and `dataTypeKeysAndroid` lists (unlike HRV in Fase 1, these two are NOT platform-split).
2. `HealthDataType.WORKOUT` data points carry the interval on the point itself (`HealthDataPoint.dateFrom`/`.dateTo`), with `.value` typed as `WorkoutHealthValue` (workout type/energy — not used by this phase). `HealthDataType.STEPS` data points use `NumericHealthValue`, same shape as `HEART_RATE`/VFC from Fase 1.
3. iOS: `STEPS` and `WORKOUT` are both covered by the same `NSHealthShareUsageDescription` key already declared in `Info.plist` (health-data-sharing permissions on iOS are granted per-type through one shared usage string, not per-key) — only the string's wording needs updating to mention them, not a new key.

---

## Task 1: New models — `EstadoEstresse`, `DiaRepouso`, `TreinoIntervalo`, and extending `BiofeedbackSummary`

**Files:**
- Create: `mobile/lib/features/biofeedback/estado_estresse.dart`
- Create: `mobile/lib/features/biofeedback/dia_repouso.dart`
- Create: `mobile/lib/features/biofeedback/treino_intervalo.dart`
- Modify: `mobile/lib/features/biofeedback/biofeedback_summary.dart`
- Modify: `mobile/test/features/biofeedback/biofeedback_summary_test.dart`
- Test: `mobile/test/features/biofeedback/dia_repouso_test.dart`

**Interfaces:**
- Produces: `EstadoEstresse { calmo, elevado, coletandoDados }`; `DiaRepouso { data: DateTime, mediaFcRepouso: double, mediaVfcRepouso: double }` with `toJson()`/`fromJson()`; `TreinoIntervalo { inicio: DateTime, fim: DateTime }`; `BiofeedbackSummary` gains a required `estadoEstresse: EstadoEstresse` field. Consumed by every later task in this plan.

- [ ] **Step 1: Write the failing test for `BiofeedbackSummary`'s new field**

Replace the full contents of `mobile/test/features/biofeedback/biofeedback_summary_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';

void main() {
  test('round-trips through toJson and fromJson with all fields present', () {
    final original = BiofeedbackSummary(
      ultimaFc: 72.0,
      mediaFcHoje: 68.5,
      mediaVfcHoje: 45.2,
      estadoEstresse: EstadoEstresse.elevado,
      atualizadoEm: DateTime.utc(2026, 8, 3, 14, 30),
    );

    final roundTripped = BiofeedbackSummary.fromJson(original.toJson());

    expect(roundTripped.ultimaFc, 72.0);
    expect(roundTripped.mediaFcHoje, 68.5);
    expect(roundTripped.mediaVfcHoje, 45.2);
    expect(roundTripped.estadoEstresse, EstadoEstresse.elevado);
    expect(roundTripped.atualizadoEm, DateTime.utc(2026, 8, 3, 14, 30));
  });

  test('round-trips with null fields (no readings yet)', () {
    final original = BiofeedbackSummary(
      ultimaFc: null,
      mediaFcHoje: null,
      mediaVfcHoje: null,
      estadoEstresse: EstadoEstresse.coletandoDados,
      atualizadoEm: DateTime.utc(2026, 8, 3, 9, 0),
    );

    final roundTripped = BiofeedbackSummary.fromJson(original.toJson());

    expect(roundTripped.ultimaFc, isNull);
    expect(roundTripped.mediaFcHoje, isNull);
    expect(roundTripped.mediaVfcHoje, isNull);
    expect(roundTripped.estadoEstresse, EstadoEstresse.coletandoDados);
  });

  test('fromJson defaults estadoEstresse to coletandoDados when the key is absent', () {
    // Resumo salvo pela Fase 1, antes deste campo existir — não pode quebrar ao ler de novo.
    final jsonAntigo = {
      'ultimaFc': 72.0,
      'mediaFcHoje': 68.5,
      'mediaVfcHoje': 45.2,
      'atualizadoEm': DateTime.utc(2026, 8, 3, 14, 30).toIso8601String(),
    };

    final lido = BiofeedbackSummary.fromJson(jsonAntigo);

    expect(lido.estadoEstresse, EstadoEstresse.coletandoDados);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_summary_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package '.../estado_estresse.dart'` (the file doesn't exist yet, and `BiofeedbackSummary` doesn't have `estadoEstresse` yet).

- [ ] **Step 3: Write the `EstadoEstresse` enum**

Create `mobile/lib/features/biofeedback/estado_estresse.dart`:

```dart
enum EstadoEstresse { calmo, elevado, coletandoDados }
```

- [ ] **Step 4: Write `TreinoIntervalo`**

Create `mobile/lib/features/biofeedback/treino_intervalo.dart`:

```dart
class TreinoIntervalo {
  const TreinoIntervalo({required this.inicio, required this.fim});

  final DateTime inicio;
  final DateTime fim;
}
```

- [ ] **Step 5: Write the failing test for `DiaRepouso`**

Create `mobile/test/features/biofeedback/dia_repouso_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/dia_repouso.dart';

void main() {
  test('round-trips through toJson and fromJson', () {
    final original = DiaRepouso(
      data: DateTime.utc(2026, 8, 3),
      mediaFcRepouso: 68.5,
      mediaVfcRepouso: 45.2,
    );

    final roundTripped = DiaRepouso.fromJson(original.toJson());

    expect(roundTripped.data, DateTime.utc(2026, 8, 3));
    expect(roundTripped.mediaFcRepouso, 68.5);
    expect(roundTripped.mediaVfcRepouso, 45.2);
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/dia_repouso_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package '.../dia_repouso.dart'`

- [ ] **Step 7: Write `DiaRepouso`**

Create `mobile/lib/features/biofeedback/dia_repouso.dart`:

```dart
class DiaRepouso {
  const DiaRepouso({
    required this.data,
    required this.mediaFcRepouso,
    required this.mediaVfcRepouso,
  });

  final DateTime data;
  final double mediaFcRepouso;
  final double mediaVfcRepouso;

  Map<String, dynamic> toJson() => {
        'data': data.toIso8601String(),
        'mediaFcRepouso': mediaFcRepouso,
        'mediaVfcRepouso': mediaVfcRepouso,
      };

  factory DiaRepouso.fromJson(Map<String, dynamic> json) {
    return DiaRepouso(
      data: DateTime.parse(json['data'] as String),
      mediaFcRepouso: (json['mediaFcRepouso'] as num).toDouble(),
      mediaVfcRepouso: (json['mediaVfcRepouso'] as num).toDouble(),
    );
  }
}
```

- [ ] **Step 8: Run the `DiaRepouso` test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/dia_repouso_test.dart`
Expected: PASS (1 test)

- [ ] **Step 9: Extend `BiofeedbackSummary` with `estadoEstresse`**

Replace the full contents of `mobile/lib/features/biofeedback/biofeedback_summary.dart` with:

```dart
import 'estado_estresse.dart';

class BiofeedbackSummary {
  const BiofeedbackSummary({
    required this.ultimaFc,
    required this.mediaFcHoje,
    required this.mediaVfcHoje,
    required this.estadoEstresse,
    required this.atualizadoEm,
  });

  final double? ultimaFc;
  final double? mediaFcHoje;
  final double? mediaVfcHoje;
  final EstadoEstresse estadoEstresse;
  final DateTime atualizadoEm;

  Map<String, dynamic> toJson() => {
        'ultimaFc': ultimaFc,
        'mediaFcHoje': mediaFcHoje,
        'mediaVfcHoje': mediaVfcHoje,
        'estadoEstresse': estadoEstresse.name,
        'atualizadoEm': atualizadoEm.toIso8601String(),
      };

  factory BiofeedbackSummary.fromJson(Map<String, dynamic> json) {
    return BiofeedbackSummary(
      ultimaFc: (json['ultimaFc'] as num?)?.toDouble(),
      mediaFcHoje: (json['mediaFcHoje'] as num?)?.toDouble(),
      mediaVfcHoje: (json['mediaVfcHoje'] as num?)?.toDouble(),
      // Resumo gravado pela Fase 1 não tem esta chave — tratamos como "ainda coletando dados"
      // em vez de quebrar a leitura de um cache pré-existente.
      estadoEstresse: json['estadoEstresse'] != null
          ? EstadoEstresse.values.byName(json['estadoEstresse'] as String)
          : EstadoEstresse.coletandoDados,
      atualizadoEm: DateTime.parse(json['atualizadoEm'] as String),
    );
  }
}
```

- [ ] **Step 10: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_summary_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 11: Commit**

```bash
git add mobile/lib/features/biofeedback/estado_estresse.dart mobile/lib/features/biofeedback/dia_repouso.dart mobile/lib/features/biofeedback/treino_intervalo.dart mobile/lib/features/biofeedback/biofeedback_summary.dart mobile/test/features/biofeedback/biofeedback_summary_test.dart mobile/test/features/biofeedback/dia_repouso_test.dart
git commit -m "feat: add EstadoEstresse, DiaRepouso, TreinoIntervalo models and extend BiofeedbackSummary"
```

---

## Task 2: Activity filtering — `BiofeedbackStressDetector.emRepouso` and `mediasEmRepouso`

**Files:**
- Create: `mobile/lib/features/biofeedback/biofeedback_stress_detector.dart`
- Test: `mobile/test/features/biofeedback/biofeedback_stress_detector_test.dart`

**Interfaces:**
- Consumes: `HealthReading` (Task 1's dependency, already exists from Fase 1); `TreinoIntervalo` (Task 1).
- Produces: `BiofeedbackStressDetector` with `emRepouso({required DateTime timestamp, required List<HealthReading> leiturasPassos, required List<TreinoIntervalo> treinos}): bool` and `mediasEmRepouso({required List<HealthReading> leiturasFc, required List<HealthReading> leiturasVfc, required List<HealthReading> leiturasPassos, required List<TreinoIntervalo> treinos}): ({double? mediaFc, double? mediaVfc})`. Consumed by Task 3 (same class, `detectar`/`atualizarHistorico`) and Task 5 (sync service).

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/features/biofeedback/biofeedback_stress_detector_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_stress_detector.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';
import 'package:sincro_mobile/features/biofeedback/treino_intervalo.dart';

void main() {
  final detector = BiofeedbackStressDetector();

  group('emRepouso', () {
    test('is false when a workout interval covers the timestamp', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 5),
        leiturasPassos: [],
        treinos: [
          TreinoIntervalo(inicio: DateTime(2026, 8, 3, 10, 0), fim: DateTime(2026, 8, 3, 10, 30)),
        ],
      );

      expect(resultado, false);
    });

    test('is false when steps in the surrounding 5-minute window reach the 15-step limiar', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 0),
        leiturasPassos: [
          HealthReading(valor: 15, timestamp: DateTime(2026, 8, 3, 10, 1)),
        ],
        treinos: [],
      );

      expect(resultado, false);
    });

    test('is true when steps in the surrounding window stay below the limiar and there is no workout', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 0),
        leiturasPassos: [
          HealthReading(valor: 14, timestamp: DateTime(2026, 8, 3, 10, 1)),
        ],
        treinos: [],
      );

      expect(resultado, true);
    });

    test('ignores steps outside the 5-minute window', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 0),
        leiturasPassos: [
          HealthReading(valor: 500, timestamp: DateTime(2026, 8, 3, 10, 10)),
        ],
        treinos: [],
      );

      expect(resultado, true);
    });

    test('is true with no steps and no workouts at all', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 0),
        leiturasPassos: [],
        treinos: [],
      );

      expect(resultado, true);
    });
  });

  group('mediasEmRepouso', () {
    test('averages only the readings that are em repouso, discarding the rest', () {
      final resultado = detector.mediasEmRepouso(
        leiturasFc: [
          HealthReading(valor: 70, timestamp: DateTime(2026, 8, 3, 8, 0)), // em repouso
          HealthReading(valor: 120, timestamp: DateTime(2026, 8, 3, 10, 0)), // durante treino
        ],
        leiturasVfc: [
          HealthReading(valor: 40, timestamp: DateTime(2026, 8, 3, 8, 0)), // em repouso
        ],
        leiturasPassos: [],
        treinos: [
          TreinoIntervalo(inicio: DateTime(2026, 8, 3, 9, 45), fim: DateTime(2026, 8, 3, 10, 15)),
        ],
      );

      expect(resultado.mediaFc, 70);
      expect(resultado.mediaVfc, 40);
    });

    test('returns null for a metric with no readings em repouso', () {
      final resultado = detector.mediasEmRepouso(
        leiturasFc: [
          HealthReading(valor: 120, timestamp: DateTime(2026, 8, 3, 10, 0)),
        ],
        leiturasVfc: [],
        leiturasPassos: [],
        treinos: [
          TreinoIntervalo(inicio: DateTime(2026, 8, 3, 9, 45), fim: DateTime(2026, 8, 3, 10, 15)),
        ],
      );

      expect(resultado.mediaFc, isNull);
      expect(resultado.mediaVfc, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_stress_detector_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package '.../biofeedback_stress_detector.dart'`

- [ ] **Step 3: Write the minimal implementation**

Create `mobile/lib/features/biofeedback/biofeedback_stress_detector.dart`:

```dart
import 'health_reading.dart';
import 'treino_intervalo.dart';

class BiofeedbackStressDetector {
  static const _meiaJanelaAtividade = Duration(seconds: 150); // janela de 5min centrada no ponto
  static const _limiarPassos = 15;

  bool emRepouso({
    required DateTime timestamp,
    required List<HealthReading> leiturasPassos,
    required List<TreinoIntervalo> treinos,
  }) {
    final duranteTreino = treinos.any(
      (t) => !timestamp.isBefore(t.inicio) && !timestamp.isAfter(t.fim),
    );
    if (duranteTreino) return false;

    final inicioJanela = timestamp.subtract(_meiaJanelaAtividade);
    final fimJanela = timestamp.add(_meiaJanelaAtividade);
    final passosNaJanela = leiturasPassos
        .where((p) => !p.timestamp.isBefore(inicioJanela) && !p.timestamp.isAfter(fimJanela))
        .fold<double>(0, (soma, p) => soma + p.valor);

    return passosNaJanela < _limiarPassos;
  }

  ({double? mediaFc, double? mediaVfc}) mediasEmRepouso({
    required List<HealthReading> leiturasFc,
    required List<HealthReading> leiturasVfc,
    required List<HealthReading> leiturasPassos,
    required List<TreinoIntervalo> treinos,
  }) {
    bool filtro(HealthReading l) => emRepouso(
          timestamp: l.timestamp,
          leiturasPassos: leiturasPassos,
          treinos: treinos,
        );

    return (
      mediaFc: _media(leiturasFc.where(filtro).toList()),
      mediaVfc: _media(leiturasVfc.where(filtro).toList()),
    );
  }

  double? _media(List<HealthReading> leituras) {
    if (leituras.isEmpty) return null;
    final soma = leituras.fold<double>(0, (total, r) => total + r.valor);
    return soma / leituras.length;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_stress_detector_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_stress_detector.dart mobile/test/features/biofeedback/biofeedback_stress_detector_test.dart
git commit -m "feat: add em-repouso activity filtering to BiofeedbackStressDetector"
```

---

## Task 3: Baseline and detection — `BiofeedbackStressDetector.detectar` and `atualizarHistorico`

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_stress_detector.dart`
- Modify: `mobile/test/features/biofeedback/biofeedback_stress_detector_test.dart`

**Interfaces:**
- Consumes: `DiaRepouso`, `EstadoEstresse` (Task 1); the class from Task 2 (extended in place, not replaced).
- Produces (added to `BiofeedbackStressDetector`): `detectar({required double? mediaFcRepousoHoje, required double? mediaVfcRepousoHoje, required List<DiaRepouso> historico, required DateTime hoje}): EstadoEstresse` and `atualizarHistorico({required List<DiaRepouso> historicoAtual, required DateTime hoje, required double? mediaFcRepousoHoje, required double? mediaVfcRepousoHoje}): List<DiaRepouso>`. Consumed by Task 5 (sync service).

- [ ] **Step 1: Write the failing tests**

Append to `mobile/test/features/biofeedback/biofeedback_stress_detector_test.dart` — add these two new `import` lines at the top, alongside the existing ones:

```dart
import 'package:sincro_mobile/features/biofeedback/dia_repouso.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';
```

Then add these two new `group`s at the end of `main()`, after the closing brace of the `mediasEmRepouso` group and before the final closing brace of `main()`:

```dart
  group('detectar', () {
    List<DiaRepouso> historicoDeDias(int quantidade, {double fc = 70, double vfc = 45}) {
      return List.generate(
        quantidade,
        (i) => DiaRepouso(
          data: DateTime(2026, 7, 20 + i),
          mediaFcRepouso: fc,
          mediaVfcRepouso: vfc,
        ),
      );
    }

    test('is coletandoDados when there are fewer than 7 days of prior history', () {
      final estado = detector.detectar(
        mediaFcRepousoHoje: 100,
        mediaVfcRepousoHoje: 20,
        historico: historicoDeDias(6),
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.coletandoDados);
    });

    test('is coletandoDados when the baseline is ready but there is no resting reading today', () {
      final estado = detector.detectar(
        mediaFcRepousoHoje: null,
        mediaVfcRepousoHoje: null,
        historico: historicoDeDias(7),
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.coletandoDados);
    });

    test('is calmo when today is within the normal range', () {
      // Histórico com um pouco de variação real (não desvio zero), hoje bem próximo da média.
      final historico = [
        DiaRepouso(data: DateTime(2026, 7, 20), mediaFcRepouso: 68, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 21), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 22), mediaFcRepouso: 72, mediaVfcRepouso: 45),
        DiaRepouso(data: DateTime(2026, 7, 23), mediaFcRepouso: 69, mediaVfcRepouso: 47),
        DiaRepouso(data: DateTime(2026, 7, 24), mediaFcRepouso: 71, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 25), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 26), mediaFcRepouso: 69, mediaVfcRepouso: 45),
      ];

      final estado = detector.detectar(
        mediaFcRepousoHoje: 71,
        mediaVfcRepousoHoje: 45,
        historico: historico,
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.calmo);
    });

    test('is calmo when only FC is elevated but VFC stays normal', () {
      // Ambas as métricas têm variação real no histórico (desvio > 0), então isolar qual
      // condição dispara depende só do valor de hoje, não de um desvio zero mascarando o efeito.
      final historicoComVariacao = [
        DiaRepouso(data: DateTime(2026, 7, 20), mediaFcRepouso: 66, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 21), mediaFcRepouso: 68, mediaVfcRepouso: 45),
        DiaRepouso(data: DateTime(2026, 7, 22), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 23), mediaFcRepouso: 72, mediaVfcRepouso: 47),
        DiaRepouso(data: DateTime(2026, 7, 24), mediaFcRepouso: 74, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 25), mediaFcRepouso: 68, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 26), mediaFcRepouso: 70, mediaVfcRepouso: 45),
      ];
      // Média/desvio da FC: ~69.71 / ~2.49 -> limiar de elevado ~73.45. Média/desvio da VFC:
      // ~45.29 / ~1.03 -> limiar de reduzida ~43.74.

      final estado = detector.detectar(
        mediaFcRepousoHoje: 100, // >= 73.45: dispara a condição de FC sozinha
        mediaVfcRepousoHoje: 45, // > 43.74: NÃO dispara a condição de VFC
        historico: historicoComVariacao,
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.calmo);
    });

    test('is elevado when both FC is elevated and VFC is reduced together', () {
      final historico = [
        DiaRepouso(data: DateTime(2026, 7, 20), mediaFcRepouso: 66, mediaVfcRepouso: 50),
        DiaRepouso(data: DateTime(2026, 7, 21), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 7, 22), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 23), mediaFcRepouso: 72, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 24), mediaFcRepouso: 74, mediaVfcRepouso: 42),
        DiaRepouso(data: DateTime(2026, 7, 25), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 7, 26), mediaFcRepouso: 70, mediaVfcRepouso: 46),
      ];

      final estado = detector.detectar(
        mediaFcRepousoHoje: 110,
        mediaVfcRepousoHoje: 20,
        historico: historico,
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.elevado);
    });

    test('never triggers elevado from a metric whose baseline has zero standard deviation', () {
      // Todo o histórico com o mesmo valor de FC -> desvio-padrão zero -> a condição de FC
      // nunca é satisfeita, mesmo com um valor de hoje muito diferente.
      final estado = detector.detectar(
        mediaFcRepousoHoje: 200,
        mediaVfcRepousoHoje: 10,
        historico: historicoDeDias(7, fc: 70, vfc: 45),
        hoje: DateTime(2026, 8, 3),
      );

      // VFC também tem desvio zero no histórico, então nenhuma das duas condições dispara.
      expect(estado, EstadoEstresse.calmo);
    });

    test('does not count an entry for today toward the minimum days required for a baseline', () {
      // Só 6 dias anteriores de verdade (21-26/jul) mais uma entrada para hoje mesmo (03/ago).
      // Se a entrada de hoje entrasse na própria contagem, o histórico pareceria ter 7 dias
      // "anteriores" e a linha de base seria considerada pronta incorretamente.
      final historicoComEntradaDeHoje = [
        ...List.generate(
          6,
          (i) => DiaRepouso(data: DateTime(2026, 7, 21 + i), mediaFcRepouso: 70, mediaVfcRepouso: 45),
        ),
        DiaRepouso(data: DateTime(2026, 8, 3), mediaFcRepouso: 70, mediaVfcRepouso: 45),
      ];

      final estado = detector.detectar(
        mediaFcRepousoHoje: 70,
        mediaVfcRepousoHoje: 45,
        historico: historicoComEntradaDeHoje,
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.coletandoDados);
    });
  });

  group('atualizarHistorico', () {
    test('appends a new entry for today when resting averages are available', () {
      final resultado = detector.atualizarHistorico(
        historicoAtual: [],
        hoje: DateTime(2026, 8, 3, 15, 0),
        mediaFcRepousoHoje: 70,
        mediaVfcRepousoHoje: 45,
      );

      expect(resultado, hasLength(1));
      expect(resultado.single.data, DateTime(2026, 8, 3));
      expect(resultado.single.mediaFcRepouso, 70);
      expect(resultado.single.mediaVfcRepouso, 45);
    });

    test('leaves the history unchanged when there is no resting reading today', () {
      final historicoAtual = [
        DiaRepouso(data: DateTime(2026, 8, 2), mediaFcRepouso: 68, mediaVfcRepouso: 44),
      ];

      final resultado = detector.atualizarHistorico(
        historicoAtual: historicoAtual,
        hoje: DateTime(2026, 8, 3, 15, 0),
        mediaFcRepousoHoje: null,
        mediaVfcRepousoHoje: 44,
      );

      expect(resultado, historicoAtual);
    });

    test('replaces an existing entry for today instead of duplicating it', () {
      final historicoAtual = [
        DiaRepouso(data: DateTime(2026, 8, 2), mediaFcRepouso: 68, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 8, 3), mediaFcRepouso: 70, mediaVfcRepouso: 45),
      ];

      final resultado = detector.atualizarHistorico(
        historicoAtual: historicoAtual,
        hoje: DateTime(2026, 8, 3, 20, 0),
        mediaFcRepousoHoje: 72,
        mediaVfcRepousoHoje: 43,
      );

      expect(resultado, hasLength(2));
      final entradaHoje = resultado.firstWhere((d) => d.data == DateTime(2026, 8, 3));
      expect(entradaHoje.mediaFcRepouso, 72);
      expect(entradaHoje.mediaVfcRepouso, 43);
    });

    test('keeps only the 14 most recent days, pruning the oldest', () {
      final historicoAtual = List.generate(
        14,
        (i) => DiaRepouso(data: DateTime(2026, 7, 21 + i), mediaFcRepouso: 70, mediaVfcRepouso: 45),
      );

      final resultado = detector.atualizarHistorico(
        historicoAtual: historicoAtual,
        hoje: DateTime(2026, 8, 4),
        mediaFcRepousoHoje: 71,
        mediaVfcRepousoHoje: 46,
      );

      expect(resultado, hasLength(14));
      expect(resultado.first.data, DateTime(2026, 7, 22)); // 21 foi podado
      expect(resultado.last.data, DateTime(2026, 8, 4));
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_stress_detector_test.dart`
Expected: FAIL — `The method 'detectar' isn't defined for the type 'BiofeedbackStressDetector'` (and similarly for `atualizarHistorico`).

- [ ] **Step 3: Write the minimal implementation**

Add these members to the `BiofeedbackStressDetector` class in
`mobile/lib/features/biofeedback/biofeedback_stress_detector.dart` (alongside `emRepouso` and
`mediasEmRepouso` from Task 2 — do not remove those), and add the two new imports at the top of
the file:

```dart
import 'dart:math';

import 'dia_repouso.dart';
import 'estado_estresse.dart';
```

```dart
  static const _minDiasBaseline = 7;
  static const _margemDesvios = 1.5;
  static const _tamanhoJanelaHistorico = 14;

  EstadoEstresse detectar({
    required double? mediaFcRepousoHoje,
    required double? mediaVfcRepousoHoje,
    required List<DiaRepouso> historico,
    required DateTime hoje,
  }) {
    final historicoAnterior = historico.where((d) => !_mesmoDia(d.data, hoje)).toList();
    if (historicoAnterior.length < _minDiasBaseline) return EstadoEstresse.coletandoDados;
    if (mediaFcRepousoHoje == null || mediaVfcRepousoHoje == null) {
      return EstadoEstresse.coletandoDados;
    }

    final statsFc = _estatisticas(historicoAnterior.map((d) => d.mediaFcRepouso).toList());
    final statsVfc = _estatisticas(historicoAnterior.map((d) => d.mediaVfcRepouso).toList());

    final fcElevada = statsFc.desvio > 0 &&
        mediaFcRepousoHoje >= statsFc.media + _margemDesvios * statsFc.desvio;
    final vfcReduzida = statsVfc.desvio > 0 &&
        mediaVfcRepousoHoje <= statsVfc.media - _margemDesvios * statsVfc.desvio;

    return (fcElevada && vfcReduzida) ? EstadoEstresse.elevado : EstadoEstresse.calmo;
  }

  List<DiaRepouso> atualizarHistorico({
    required List<DiaRepouso> historicoAtual,
    required DateTime hoje,
    required double? mediaFcRepousoHoje,
    required double? mediaVfcRepousoHoje,
  }) {
    if (mediaFcRepousoHoje == null || mediaVfcRepousoHoje == null) return historicoAtual;

    final dataHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final semEntradaDeHoje = historicoAtual.where((d) => !_mesmoDia(d.data, hoje)).toList();
    final atualizado = [
      ...semEntradaDeHoje,
      DiaRepouso(
        data: dataHoje,
        mediaFcRepouso: mediaFcRepousoHoje,
        mediaVfcRepouso: mediaVfcRepousoHoje,
      ),
    ]..sort((a, b) => a.data.compareTo(b.data));

    if (atualizado.length > _tamanhoJanelaHistorico) {
      return atualizado.sublist(atualizado.length - _tamanhoJanelaHistorico);
    }
    return atualizado;
  }

  ({double media, double desvio}) _estatisticas(List<double> valores) {
    final media = valores.reduce((a, b) => a + b) / valores.length;
    final variancia =
        valores.fold<double>(0, (soma, v) => soma + pow(v - media, 2)) / valores.length;
    return (media: media, desvio: sqrt(variancia));
  }

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_stress_detector_test.dart`
Expected: PASS (18 tests — 7 from Task 2 plus 11 new)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_stress_detector.dart mobile/test/features/biofeedback/biofeedback_stress_detector_test.dart
git commit -m "feat: add baseline comparison and rolling history to BiofeedbackStressDetector"
```

---

## Task 4: Cache — resting history storage

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_cache.dart`
- Modify: `mobile/test/features/biofeedback/biofeedback_cache_test.dart`

**Interfaces:**
- Consumes: `DiaRepouso` (Task 1).
- Produces (added to `BiofeedbackCache`): `getHistoricoRepouso(): Future<List<DiaRepouso>>` (empty list if nothing saved), `setHistoricoRepouso(List<DiaRepouso>): Future<void>`; `clear()` extended to also erase this key. Consumed by Task 5 (sync service).

- [ ] **Step 1: Write the failing tests**

Add this import to the top of `mobile/test/features/biofeedback/biofeedback_cache_test.dart`,
alongside the existing ones:

```dart
import 'package:sincro_mobile/features/biofeedback/dia_repouso.dart';
```

Then add these tests inside `main()`, after the existing `clear removes ativo, frequencia, and
resumo together` test and before the final closing brace:

```dart
  test('getHistoricoRepouso returns an empty list when nothing was ever saved', () async {
    final cache = BiofeedbackCache();

    expect(await cache.getHistoricoRepouso(), isEmpty);
  });

  test('setHistoricoRepouso then getHistoricoRepouso round-trips the list', () async {
    final cache = BiofeedbackCache();
    final historico = [
      DiaRepouso(data: DateTime.utc(2026, 8, 1), mediaFcRepouso: 68, mediaVfcRepouso: 44),
      DiaRepouso(data: DateTime.utc(2026, 8, 2), mediaFcRepouso: 70, mediaVfcRepouso: 45),
    ];

    await cache.setHistoricoRepouso(historico);
    final lido = await cache.getHistoricoRepouso();

    expect(lido, hasLength(2));
    expect(lido[0].data, DateTime.utc(2026, 8, 1));
    expect(lido[1].mediaFcRepouso, 70);
  });

  test('clear also removes the historico de repouso', () async {
    final cache = BiofeedbackCache();
    await cache.setHistoricoRepouso([
      DiaRepouso(data: DateTime.utc(2026, 8, 1), mediaFcRepouso: 68, mediaVfcRepouso: 44),
    ]);

    await cache.clear();

    expect(await cache.getHistoricoRepouso(), isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_cache_test.dart`
Expected: FAIL — `The method 'getHistoricoRepouso' isn't defined for the type 'BiofeedbackCache'`

- [ ] **Step 3: Write the minimal implementation**

Replace the full contents of `mobile/lib/features/biofeedback/biofeedback_cache.dart` with:

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'biofeedback_summary.dart';
import 'dia_repouso.dart';

const _chaveAtivo = 'biofeedback_ativo';
const _chaveFrequenciaMinutos = 'biofeedback_frequencia_minutos';
const _chaveResumo = 'biofeedback_resumo';
const _chaveHistoricoRepouso = 'biofeedback_historico_repouso';
const _frequenciaPadraoMinutos = 30;

class BiofeedbackCache {
  /// `SharedPreferencesAsync` — e não a API legada `SharedPreferences.getInstance()` — porque a
  /// sincronização em background roda em um isolate separado. A API legada mantém um cache em
  /// memória por isolate, preenchido uma única vez: o isolate principal nunca enxergaria o resumo
  /// gravado pelo isolate do background e o app continuaria mostrando dados velhos. Esta API não
  /// cacheia nada em memória, sempre lê do armazenamento nativo.
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<bool> isAtivo() async {
    return await _prefs.getBool(_chaveAtivo) ?? false;
  }

  Future<void> setAtivo(bool ativo) {
    return _prefs.setBool(_chaveAtivo, ativo);
  }

  Future<int> getFrequenciaMinutos() async {
    return await _prefs.getInt(_chaveFrequenciaMinutos) ?? _frequenciaPadraoMinutos;
  }

  Future<void> setFrequenciaMinutos(int minutos) {
    return _prefs.setInt(_chaveFrequenciaMinutos, minutos);
  }

  Future<BiofeedbackSummary?> getResumo() async {
    final raw = await _prefs.getString(_chaveResumo);
    if (raw == null) return null;
    return BiofeedbackSummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setResumo(BiofeedbackSummary resumo) {
    return _prefs.setString(_chaveResumo, jsonEncode(resumo.toJson()));
  }

  Future<List<DiaRepouso>> getHistoricoRepouso() async {
    final raw = await _prefs.getString(_chaveHistoricoRepouso);
    if (raw == null) return [];
    final lista = jsonDecode(raw) as List<dynamic>;
    return lista.map((e) => DiaRepouso.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setHistoricoRepouso(List<DiaRepouso> historico) {
    final lista = historico.map((d) => d.toJson()).toList();
    return _prefs.setString(_chaveHistoricoRepouso, jsonEncode(lista));
  }

  Future<void> clear() async {
    await _prefs.remove(_chaveAtivo);
    await _prefs.remove(_chaveFrequenciaMinutos);
    await _prefs.remove(_chaveResumo);
    await _prefs.remove(_chaveHistoricoRepouso);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_cache_test.dart`
Expected: PASS (10 tests — 7 from Fase 1 plus 3 new)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_cache.dart mobile/test/features/biofeedback/biofeedback_cache_test.dart
git commit -m "feat: add resting-history storage to BiofeedbackCache"
```

---

## Task 5: Health service — reading `STEPS` and `WORKOUT`, and platform manifests

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_health_service.dart`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `mobile/ios/Runner/Info.plist`

**Interfaces:**
- Consumes: `HealthReading`, `TreinoIntervalo` (Task 1).
- Produces (added to `BiofeedbackHealthService`): `lerPassosHoje(): Future<List<HealthReading>>`, `lerTreinosHoje(): Future<List<TreinoIntervalo>>`; the permission set requested by `solicitarPermissao()` grows to include `STEPS` and `WORKOUT`. Consumed by Task 6 (sync service).

This file wraps the `health` package's platform channel — same situation as Fase 1's Task 4, no
automated test. Verified via `flutter analyze` plus the manual device check called out in the
spec's Testes section.

- [ ] **Step 1: Add the Android permissions**

Edit `mobile/android/app/src/main/AndroidManifest.xml` — add these two lines as siblings of the
two existing `<uses-permission>` entries at the top of the file (per this plan's Prerequisites,
confirmed against the resolved `health-13.3.1` package):

```xml
    <uses-permission android:name="android.permission.health.READ_STEPS" />
    <uses-permission android:name="android.permission.health.READ_EXERCISE" />
```

The file's first lines become:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.health.READ_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_HEART_RATE_VARIABILITY" />
    <uses-permission android:name="android.permission.health.READ_STEPS" />
    <uses-permission android:name="android.permission.health.READ_EXERCISE" />
    <application
```

- [ ] **Step 2: Update the iOS usage description**

Edit `mobile/ios/Runner/Info.plist` — replace the `NSHealthShareUsageDescription` string (per this
plan's Prerequisites, `STEPS`/`WORKOUT` are covered by this same key, only the wording needs to
mention them):

```xml
	<key>NSHealthShareUsageDescription</key>
	<string>O Sincro usa dados de frequência cardíaca, passos e treinos do seu smartwatch para mostrar um resumo calmo do seu bem-estar.</string>
```

- [ ] **Step 3: Write the implementation**

Replace the full contents of `mobile/lib/features/biofeedback/biofeedback_health_service.dart`
with:

```dart
import 'dart:io';

import 'package:health/health.dart';
import 'health_reading.dart';
import 'treino_intervalo.dart';

/// Métrica de variabilidade cardíaca disponível em cada plataforma: o HealthKit expõe SDNN e o
/// Health Connect expõe RMSSD (o `health` não oferece SDNN no Android, e a permissão declarada no
/// AndroidManifest, `READ_HEART_RATE_VARIABILITY`, é justamente a de RMSSD). SDNN e RMSSD são
/// métricas diferentes e não são diretamente comparáveis entre si; aqui as duas são tratadas
/// simplesmente como "vfc" em milissegundos, o que é aceitável porque o app só mostra um resumo
/// calmo do próprio usuário, sem comparar um aparelho com o outro.
HealthDataType get _tipoVfc => Platform.isIOS
    ? HealthDataType.HEART_RATE_VARIABILITY_SDNN
    : HealthDataType.HEART_RATE_VARIABILITY_RMSSD;

class BiofeedbackHealthService {
  final Health _health = Health();

  Future<void>? _configuracao;

  /// `configure()` precisa rodar uma vez antes de qualquer uso do plugin. O Future é guardado
  /// para que chamadas concorrentes compartilhem a mesma configuração em vez de repeti-la.
  Future<void> _garantirConfigurado() => _configuracao ??= _health.configure();

  List<HealthDataType> get _tipos =>
      [HealthDataType.HEART_RATE, _tipoVfc, HealthDataType.STEPS, HealthDataType.WORKOUT];

  Future<bool> solicitarPermissao() async {
    await _garantirConfigurado();
    final tipos = _tipos;
    return _health.requestAuthorization(
      tipos,
      permissions: tipos.map((_) => HealthDataAccess.READ).toList(),
    );
  }

  Future<List<HealthReading>> lerFrequenciaCardiacaHoje() {
    return _lerTipoHoje(HealthDataType.HEART_RATE);
  }

  Future<List<HealthReading>> lerVariabilidadeHoje() {
    return _lerTipoHoje(_tipoVfc);
  }

  Future<List<HealthReading>> lerPassosHoje() {
    return _lerTipoHoje(HealthDataType.STEPS);
  }

  Future<List<TreinoIntervalo>> lerTreinosHoje() async {
    await _garantirConfigurado();
    final agora = DateTime.now();
    final inicioDoDia = DateTime(agora.year, agora.month, agora.day);
    final pontos = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT],
      startTime: inicioDoDia,
      endTime: agora,
    );
    return pontos
        .map((p) => TreinoIntervalo(inicio: p.dateFrom, fim: p.dateTo))
        .toList();
  }

  Future<List<HealthReading>> _lerTipoHoje(HealthDataType tipo) async {
    await _garantirConfigurado();
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

- [ ] **Step 4: Verify it compiles**

Run: `cd mobile && flutter analyze lib/features/biofeedback/biofeedback_health_service.dart`
Expected: "No issues found!" — `WORKOUT` data points use `.dateFrom`/`.dateTo` directly (not
`.value` as `NumericHealthValue`, which would throw a cast error) — this is why `lerTreinosHoje`
does not reuse the private `_lerTipoHoje` helper.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_health_service.dart mobile/android/app/src/main/AndroidManifest.xml mobile/ios/Runner/Info.plist
git commit -m "feat: read STEPS and WORKOUT from HealthKit/Health Connect"
```

---

## Task 6: Sync service — wiring the detection pipeline

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_sync_service.dart`
- Modify: `mobile/test/features/biofeedback/biofeedback_sync_service_test.dart`

**Interfaces:**
- Consumes: `BiofeedbackHealthService.lerPassosHoje()`/`lerTreinosHoje()` (Task 5);
  `BiofeedbackCache.getHistoricoRepouso()`/`setHistoricoRepouso()` (Task 4);
  `BiofeedbackStressDetector.mediasEmRepouso()`/`detectar()`/`atualizarHistorico()` (Tasks 2-3).
- Produces: `BiofeedbackSyncService`'s constructor gains a 4th positional parameter,
  `BiofeedbackStressDetector`; `sincronizar()`'s behavior is extended (signature unchanged).
  Consumed by Task 7 (providers) and Task 8 (background task callback).

- [ ] **Step 1: Write the failing tests**

Replace the full contents of `mobile/test/features/biofeedback/biofeedback_sync_service_test.dart`
with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

class MockBiofeedbackHealthService extends Mock implements BiofeedbackHealthService {}

class MockBiofeedbackCache extends Mock implements BiofeedbackCache {}

class FakeBiofeedbackSummary extends Fake implements BiofeedbackSummary {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeBiofeedbackSummary());
  });

  BiofeedbackSyncService buildService(
    MockBiofeedbackHealthService healthService,
    MockBiofeedbackCache cache, {
    List<HealthReading> passos = const [],
    List<TreinoIntervalo> treinos = const [],
    List<DiaRepouso> historico = const [],
  }) {
    when(() => healthService.lerPassosHoje()).thenAnswer((_) async => passos);
    when(() => healthService.lerTreinosHoje()).thenAnswer((_) async => treinos);
    when(() => cache.getHistoricoRepouso()).thenAnswer((_) async => historico);
    when(() => cache.setHistoricoRepouso(any())).thenAnswer((_) async {});
    when(() => cache.setResumo(any())).thenAnswer((_) async {});
    return BiofeedbackSyncService(
      healthService,
      cache,
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
    );
  }

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
    final service = buildService(healthService, cache);

    await service.sincronizar(agora: agora);

    final captured = verify(() => cache.setResumo(captureAny())).captured;
    final salvo = captured.single as BiofeedbackSummary;
    expect(salvo.ultimaFc, 80);
    expect(salvo.mediaFcHoje, 80);
    expect(salvo.mediaVfcHoje, 45);
    expect(salvo.atualizadoEm, agora);
  });

  test('saves an all-null summary with coletandoDados when there are no readings yet', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer((_) async => []);
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer((_) async => []);
    final service = buildService(healthService, cache);

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    final captured = verify(() => cache.setResumo(captureAny())).captured;
    final salvo = captured.single as BiofeedbackSummary;
    expect(salvo.ultimaFc, isNull);
    expect(salvo.estadoEstresse, EstadoEstresse.coletandoDados);
  });

  test('discards readings during a workout when computing the resting history entry', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [
        HealthReading(valor: 70, timestamp: DateTime(2026, 8, 3, 8, 0)), // em repouso
        HealthReading(valor: 150, timestamp: DateTime(2026, 8, 3, 10, 0)), // durante treino
      ],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 45, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      treinos: [
        TreinoIntervalo(inicio: DateTime(2026, 8, 3, 9, 45), fim: DateTime(2026, 8, 3, 10, 15)),
      ],
    );

    await service.sincronizar(agora: agora);

    final captured = verify(() => cache.setHistoricoRepouso(captureAny())).captured;
    final historicoSalvo = captured.single as List<DiaRepouso>;
    expect(historicoSalvo, hasLength(1));
    // Só a leitura em repouso (70) entra na média do dia — a de 150 durante o treino é descartada.
    expect(historicoSalvo.single.mediaFcRepouso, 70);
  });

  test('detects elevado when today is far outside a stable 7-day baseline', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final historicoEstavel = [
      DiaRepouso(data: DateTime(2026, 7, 27), mediaFcRepouso: 66, mediaVfcRepouso: 50),
      DiaRepouso(data: DateTime(2026, 7, 28), mediaFcRepouso: 68, mediaVfcRepouso: 48),
      DiaRepouso(data: DateTime(2026, 7, 29), mediaFcRepouso: 70, mediaVfcRepouso: 46),
      DiaRepouso(data: DateTime(2026, 7, 30), mediaFcRepouso: 72, mediaVfcRepouso: 44),
      DiaRepouso(data: DateTime(2026, 7, 31), mediaFcRepouso: 74, mediaVfcRepouso: 42),
      DiaRepouso(data: DateTime(2026, 8, 1), mediaFcRepouso: 68, mediaVfcRepouso: 48),
      DiaRepouso(data: DateTime(2026, 8, 2), mediaFcRepouso: 70, mediaVfcRepouso: 46),
    ];
    final service = buildService(healthService, cache, historico: historicoEstavel);

    await service.sincronizar(agora: agora);

    final captured = verify(() => cache.setResumo(captureAny())).captured;
    final salvo = captured.single as BiofeedbackSummary;
    expect(salvo.estadoEstresse, EstadoEstresse.elevado);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_sync_service_test.dart`
Expected: FAIL — constructor `BiofeedbackSyncService` doesn't accept 4 positional arguments yet,
and `healthService.lerPassosHoje()`/`lerTreinosHoje()` don't exist on the mock's stubbed surface
until `BiofeedbackHealthService` (Task 5) declares them.

- [ ] **Step 3: Write the minimal implementation**

Replace the full contents of `mobile/lib/features/biofeedback/biofeedback_sync_service.dart` with:

```dart
import 'biofeedback_cache.dart';
import 'biofeedback_health_service.dart';
import 'biofeedback_stress_detector.dart';
import 'biofeedback_summary.dart';
import 'biofeedback_summary_calculator.dart';

class BiofeedbackSyncService {
  BiofeedbackSyncService(this._healthService, this._cache, this._calculator, this._detector);

  final BiofeedbackHealthService _healthService;
  final BiofeedbackCache _cache;
  final BiofeedbackSummaryCalculator _calculator;
  final BiofeedbackStressDetector _detector;

  Future<void> sincronizar({DateTime? agora}) async {
    final agoraEfetivo = agora ?? DateTime.now();
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
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/biofeedback/biofeedback_sync_service_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_sync_service.dart mobile/test/features/biofeedback/biofeedback_sync_service_test.dart
git commit -m "feat: wire stress detection into BiofeedbackSyncService"
```

---

## Task 7: Wire the detector into providers and the background task

**Files:**
- Modify: `mobile/lib/features/biofeedback/biofeedback_providers.dart`
- Modify: `mobile/lib/features/biofeedback/biofeedback_background_task.dart`

**Interfaces:**
- Consumes: `BiofeedbackStressDetector` (Tasks 2-3); `BiofeedbackSyncService`'s new constructor
  shape (Task 6).
- Produces: `biofeedbackSyncServiceProvider` continues to expose the same `BiofeedbackSyncService`
  type, just constructed with the extra dependency; the background isolate's callback does the
  same. No new provider names — nothing downstream (Task 8) needs to change because of this task.

No test for this file — it's pure dependency wiring with no logic of its own, same reasoning as
Fase 1's equivalent task.

- [ ] **Step 1: Update the providers file**

In `mobile/lib/features/biofeedback/biofeedback_providers.dart`, add this import alongside the
existing ones:

```dart
import 'biofeedback_stress_detector.dart';
```

Then change this exact line inside `biofeedbackSyncServiceProvider`:

```dart
final biofeedbackSyncServiceProvider = Provider<BiofeedbackSyncService>((ref) {
  return BiofeedbackSyncService(
    ref.watch(biofeedbackHealthServiceProvider),
    ref.watch(biofeedbackCacheProvider),
    BiofeedbackSummaryCalculator(),
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
  );
});
```

- [ ] **Step 2: Update the background task callback**

In `mobile/lib/features/biofeedback/biofeedback_background_task.dart`, add this import alongside
the existing ones:

```dart
import 'biofeedback_stress_detector.dart';
```

Then change this exact block inside `biofeedbackCallbackDispatcher`:

```dart
    final syncService = BiofeedbackSyncService(
      BiofeedbackHealthService(),
      BiofeedbackCache(),
      BiofeedbackSummaryCalculator(),
    );
```

to:

```dart
    final syncService = BiofeedbackSyncService(
      BiofeedbackHealthService(),
      BiofeedbackCache(),
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
    );
```

- [ ] **Step 3: Verify it compiles**

Run: `cd mobile && flutter analyze lib/features/biofeedback/biofeedback_providers.dart lib/features/biofeedback/biofeedback_background_task.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/features/biofeedback/biofeedback_providers.dart mobile/lib/features/biofeedback/biofeedback_background_task.dart
git commit -m "feat: wire BiofeedbackStressDetector into providers and background task"
```

---

## Task 8: UI — show the stress state on the Home card and detail screen

**Files:**
- Modify: `mobile/lib/features/home/home_screen.dart`
- Modify: `mobile/lib/features/biofeedback/biofeedback_screen.dart`
- Modify: `mobile/lib/features/biofeedback/biofeedback_providers.dart`

**Interfaces:**
- Consumes: `biofeedbackResumoProvider` (already exists, now resolves a `BiofeedbackSummary` whose
  `estadoEstresse` is populated); `EstadoEstresse` (Task 1); `BiofeedbackCache.getHistoricoRepouso()`
  (Task 4).
- Produces: `biofeedbackDiasNoHistoricoProvider` (`FutureProvider.autoDispose<int>`), new in this
  task, consumed only by this task's own UI change.

No automated test — same reasoning as Fase 1's UI tasks: this codebase doesn't widget-test these
screens; verified via `flutter analyze` and the manual device check.

- [ ] **Step 1: Update the Home card's subtitle**

In `mobile/lib/features/home/home_screen.dart`, add this import alongside the existing ones:

```dart
import '../biofeedback/estado_estresse.dart';
```

Then replace the `_UltimaFcSubtitle` class (currently at the end of the file) with:

```dart
/// Mostrada só quando o Biofeedback já está ativo (ver `_BiofeedbackCard.build`), então "nenhum
/// dado disponível ainda" aqui significa "ativado mas sem smartwatch pareado", não "não ativado".
class _UltimaFcSubtitle extends ConsumerWidget {
  const _UltimaFcSubtitle();

  static String _rotuloEstado(EstadoEstresse estado) {
    switch (estado) {
      case EstadoEstresse.calmo:
        return 'Calmo';
      case EstadoEstresse.elevado:
        return 'Elevado';
      case EstadoEstresse.coletandoDados:
        // Não menciona "coletando dados" na Home — a tela de detalhe é o lugar para isso, para
        // a Home (primeiro contato do app) não parecer ter uma pendência.
        return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumoAsync = ref.watch(biofeedbackResumoProvider);
    return resumoAsync.when(
      data: (resumo) {
        if (resumo?.ultimaFc == null) return const Text('Nenhum dado disponível ainda');
        // Sem "agora": a última leitura pode ter horas, já que a sincronização é periódica.
        final rotuloEstado = _rotuloEstado(resumo!.estadoEstresse);
        final texto = rotuloEstado.isEmpty
            ? '${resumo.ultimaFc!.round()} bpm'
            : '${resumo.ultimaFc!.round()} bpm · $rotuloEstado';
        return Text(texto);
      },
      loading: () => const Text('Carregando...'),
      error: (_, __) => const Text('Nenhum dado disponível ainda'),
    );
  }
}
```

- [ ] **Step 2: Add the state line to the detail screen**

In `mobile/lib/features/biofeedback/biofeedback_screen.dart`, add this import alongside the
existing ones:

```dart
import 'estado_estresse.dart';
```

Then add this static method to the `_BiofeedbackContent` class, alongside the existing
`_mesmoDia`/`_rotulos` static methods:

```dart
  static String _rotuloEstadoEstresse(EstadoEstresse estado, int diasNoHistorico) {
    switch (estado) {
      case EstadoEstresse.calmo:
        return 'Calmo';
      case EstadoEstresse.elevado:
        return 'Elevado';
      case EstadoEstresse.coletandoDados:
        return 'Coletando dados ($diasNoHistorico de 7 dias)';
    }
  }
```

`_BiofeedbackContent` does not currently know how many days are in the resting history — that
number lives only in the cache, one layer up. Change `BiofeedbackScreen.build` (in the same file)
from:

```dart
        child: resumoAsync.when(
          data: (resumo) => _BiofeedbackContent(resumo: resumo),
```

to:

```dart
        child: resumoAsync.when(
          data: (resumo) => _BiofeedbackContent(
            resumo: resumo,
            diasNoHistoricoAsync: ref.watch(biofeedbackDiasNoHistoricoProvider),
          ),
```

Add this new provider to `mobile/lib/features/biofeedback/biofeedback_providers.dart`, alongside
the other `FutureProvider.autoDispose` declarations:

```dart
final biofeedbackDiasNoHistoricoProvider = FutureProvider.autoDispose<int>((ref) async {
  final historico = await ref.watch(biofeedbackCacheProvider).getHistoricoRepouso();
  final hoje = DateTime.now();
  return historico.where((d) => !(d.data.year == hoje.year && d.data.month == hoje.month && d.data.day == hoje.day)).length;
});
```

Now update `_BiofeedbackContent` in `biofeedback_screen.dart`: change its constructor and add the
new field —

```dart
class _BiofeedbackContent extends StatelessWidget {
  const _BiofeedbackContent({required this.resumo, required this.diasNoHistoricoAsync});

  final BiofeedbackSummary? resumo;
  final AsyncValue<int> diasNoHistoricoAsync;
```

Add this import to `biofeedback_screen.dart` (needed for `AsyncValue`):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Finally, add the state text as a new `Text` widget inside `_BiofeedbackContent.build`'s `ListView`
`children`, right after the closing `),` of the VFC `Card` and before the existing `SizedBox` +
"Atualizado" `Text`:

```dart
        const SizedBox(height: 16),
        Text(
          diasNoHistoricoAsync.when(
            data: (dias) => _rotuloEstadoEstresse(atual.estadoEstresse, dias),
            loading: () => 'Carregando...',
            error: (_, __) => _rotuloEstadoEstresse(atual.estadoEstresse, 0),
          ),
          style: const TextStyle(fontSize: 14),
        ),
```

- [ ] **Step 3: Verify it compiles**

Run: `cd mobile && flutter analyze`
Expected: "No issues found!"

Then run the full mobile test suite to confirm nothing else broke: `cd mobile && flutter test`
Expected: PASS (all tests)

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/features/home/home_screen.dart mobile/lib/features/biofeedback/biofeedback_screen.dart mobile/lib/features/biofeedback/biofeedback_providers.dart
git commit -m "feat: show estado de estresse on the Home card and Biofeedback detail screen"
```

---

## Plan Self-Review Notes

**Spec coverage:**
- Estado de estresse na Home junto da FC → Task 8 (`_UltimaFcSubtitle`).
- Estado de estresse na tela de detalhe, com contagem de dias durante `coletandoDados` → Task 8
  (`_BiofeedbackContent` + `biofeedbackDiasNoHistoricoProvider`).
- Linha de base automática, sem calibração manual → Tasks 2-3 (`BiofeedbackStressDetector`), Task
  6 (sync service never asks for user input).
- Filtragem de atividade física (passos + treino) → Task 2 (`emRepouso`).
- Janela de 14 dias, mínimo de 7 dias, margem de 1,5 desvio-padrão, limiar de 15 passos → all
  encoded as named constants in `BiofeedbackStressDetector` (Tasks 2-3), matching the Global
  Constraints section verbatim.
- Zero mudança de backend → no task in this plan touches `backend/`; confirmed by inspection —
  every file this plan creates or modifies is under `mobile/`.
- Desativar apaga o histórico de repouso → Task 4 (`BiofeedbackCache.clear()` extended).
- Sem alertas/notificações (Fase 3 fica de fora) → no task in this plan adds any notification,
  push, or intervention — only passive text display.

**Placeholder scan:** No TBD/TODO. Task 5 (health service) has no automated test by design
(documented in the spec and Fase 1's equivalent task), not a missing decision — it has concrete,
complete code and a concrete verification step.

**Type consistency:** `EstadoEstresse`, `DiaRepouso`, `TreinoIntervalo` (Task 1) are used with
identical field/method names across every later task. `BiofeedbackStressDetector`'s method names
(`emRepouso`, `mediasEmRepouso`, `detectar`, `atualizarHistorico`) match exactly between their
defining tasks (2-3) and every consumer (Task 6). `BiofeedbackCache.getHistoricoRepouso`/
`setHistoricoRepouso` (Task 4) match exactly in Task 6's sync service and Task 8's new provider.
`BiofeedbackHealthService.lerPassosHoje`/`lerTreinosHoje` (Task 5) match exactly in Task 6's sync
service.

**Deferred (explicitly out of scope, from the approved spec):**
- Alertas/intervenção de estresse (Fase 3 deste pilar).
- Persistência no backend de qualquer dado ou linha de base desta fase.
- Calibração manual, thresholds configuráveis pelo usuário, estados graduados de estresse.
- Métricas além de FC, VFC, passos e treinos.
