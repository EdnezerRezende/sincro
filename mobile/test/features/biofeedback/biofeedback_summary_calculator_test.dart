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
