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
