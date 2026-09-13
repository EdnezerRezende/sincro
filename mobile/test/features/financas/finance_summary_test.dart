import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';

void main() {
  test('FinanceSummary.fromJson parses the 5-field resumo shape', () {
    final summary = FinanceSummary.fromJson({
      'saldoLivre': 1234.56,
      'saldoContas': 2000.0,
      'faturasAbertas': 450.0,
      'despesasPendentesCiclo': 300.0,
      'cicloFim': '2026-09-30T00:00:00.000Z',
    });

    expect(summary.saldoLivre, 1234.56);
    expect(summary.saldoContas, 2000.0);
    expect(summary.faturasAbertas, 450.0);
    expect(summary.despesasPendentesCiclo, 300.0);
    expect(summary.cicloFim, DateTime.utc(2026, 9, 30));
  });
}
