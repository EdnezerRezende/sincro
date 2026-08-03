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
