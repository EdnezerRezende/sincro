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
