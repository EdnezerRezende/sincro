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
