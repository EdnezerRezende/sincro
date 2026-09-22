import 'biofeedback_summary.dart';
import 'estado_estresse.dart';
import 'health_reading.dart';

class BiofeedbackSummaryCalculator {
  BiofeedbackSummary calcular({
    required List<HealthReading> leiturasFc,
    required List<HealthReading> leiturasVfc,
    required DateTime agora,
  }) {
    final maisRecente = _maisRecente(leiturasFc);
    return BiofeedbackSummary(
      ultimaFc: maisRecente?.valor,
      ultimaFcEm: maisRecente?.timestamp,
      mediaFcHoje: _media(leiturasFc),
      mediaVfcHoje: _media(leiturasVfc),
      // Placeholder: `BiofeedbackSyncService` sobrescreve com o estado real detectado. O cálculo
      // aqui não tem acesso ao detector nem ao histórico de repouso para decidir isso.
      estadoEstresse: EstadoEstresse.coletandoDados,
      atualizadoEm: agora,
    );
  }

  HealthReading? _maisRecente(List<HealthReading> leituras) {
    if (leituras.isEmpty) return null;
    return leituras.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);
  }

  double? _media(List<HealthReading> leituras) {
    if (leituras.isEmpty) return null;
    final soma = leituras.fold<double>(0, (total, r) => total + r.valor);
    return soma / leituras.length;
  }
}
