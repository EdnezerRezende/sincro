import 'dart:math';

import 'dia_repouso.dart';
import 'estado_estresse.dart';
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
}
