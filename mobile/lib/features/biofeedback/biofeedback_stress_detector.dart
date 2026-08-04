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
