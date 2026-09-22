import 'dart:math';

import 'dia_repouso.dart';
import 'estado_estresse.dart';
import 'health_reading.dart';
import 'linha_de_base.dart';
import 'treino_intervalo.dart';

class BiofeedbackStressDetector {
  static const _meiaJanelaAtividade = Duration(seconds: 150); // janela de 5min centrada no ponto
  static const _limiarPassos = 15;

  /// Amostras de passos mais longas que isto são ignoradas pelo filtro de repouso. Um único
  /// registro cobrindo o dia inteiro ("8 000 passos entre 00:00 e 24:00", como alguns apps de
  /// saúde gravam) não diz *quando* a pessoa andou: espalhá-lo pelas 24 h marcaria até a madrugada
  /// como atividade, o dia nunca entraria na linha de base e o app voltaria a ficar preso em
  /// "Coletando dados". Sem informação de horário, o filtro trata o período como repouso.
  static const duracaoMaximaAmostraPassos = Duration(hours: 1);

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
    final passosNaJanela = leiturasPassos.fold<double>(
      0,
      (soma, p) => soma + _passosDentroDaJanela(p, inicioJanela, fimJanela),
    );

    return passosNaJanela < _limiarPassos;
  }

  /// Parte dos passos de uma amostra que cai dentro da janela [inicio, fim].
  ///
  /// O relógio grava passos por intervalo ("137 passos entre 09:10 e 09:20"), não por instante.
  /// Comparar só o começo do intervalo com a janela de 5 minutos deixava uma caminhada inteira
  /// passar como repouso sempre que o intervalo começava antes da janela — e a média "em repouso"
  /// subia com leituras feitas andando. Os passos são atribuídos proporcionalmente à sobreposição
  /// entre o intervalo da amostra e a janela; uma amostra instantânea conta inteira se estiver
  /// dentro da janela.
  static double _passosDentroDaJanela(HealthReading amostra, DateTime inicio, DateTime fim) {
    final duracao = amostra.fim.difference(amostra.timestamp);
    if (duracao > duracaoMaximaAmostraPassos) return 0;
    if (duracao <= Duration.zero) {
      final dentro = !amostra.timestamp.isBefore(inicio) && !amostra.timestamp.isAfter(fim);
      return dentro ? amostra.valor : 0;
    }
    final inicioSobreposicao = amostra.timestamp.isAfter(inicio) ? amostra.timestamp : inicio;
    final fimSobreposicao = amostra.fim.isBefore(fim) ? amostra.fim : fim;
    final sobreposicao = fimSobreposicao.difference(inicioSobreposicao);
    if (sobreposicao <= Duration.zero) return 0;
    return amostra.valor * sobreposicao.inMilliseconds / duracao.inMilliseconds;
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

  static const minDiasBaseline = 7;

  /// Margem quando FC e VFC decidem juntas (regra da spec: as duas condições precisam valer).
  static const margemDesvios = 1.5;

  /// Margem quando só a FC está disponível: sem a segunda condição (VFC reduzida) para confirmar,
  /// a exigência sobre a única métrica sobe para compensar a perda do segundo sinal.
  static const margemDesviosSoFc = 2.0;

  static const _tamanhoJanelaHistorico = 14;

  /// Linha de base a partir dos dias anteriores a [hoje]; `null` enquanto houver menos de
  /// [minDiasBaseline] dias. A parte de VFC só entra quando ela também tem dias suficientes.
  LinhaDeBase? linhaDeBase({required List<DiaRepouso> historico, required DateTime hoje}) {
    final anteriores = historico.where((d) => !_mesmoDia(d.data, hoje)).toList();
    if (anteriores.length < minDiasBaseline) return null;

    final fc = _estatisticas(anteriores.map((d) => d.mediaFcRepouso).toList());
    final valoresVfc = anteriores.map((d) => d.mediaVfcRepouso).whereType<double>().toList();
    final vfc = valoresVfc.length >= minDiasBaseline ? _estatisticas(valoresVfc) : null;
    return LinhaDeBase(
      dias: anteriores.length,
      fcMedia: fc.media,
      fcDesvio: fc.desvio,
      vfcMedia: vfc?.media,
      vfcDesvio: vfc?.desvio,
    );
  }

  EstadoEstresse detectar({
    required double? mediaFcRepousoHoje,
    required double? mediaVfcRepousoHoje,
    required List<DiaRepouso> historico,
    required DateTime hoje,
  }) {
    final base = linhaDeBase(historico: historico, hoje: hoje);
    if (base == null || mediaFcRepousoHoje == null) return EstadoEstresse.coletandoDados;

    if (base.temVfc && mediaVfcRepousoHoje != null) {
      final fcElevada = base.fcDesvio > 0 &&
          mediaFcRepousoHoje >= base.fcMedia + margemDesvios * base.fcDesvio;
      final vfcReduzida = base.vfcDesvio! > 0 &&
          mediaVfcRepousoHoje <= base.vfcMedia! - margemDesvios * base.vfcDesvio!;
      return (fcElevada && vfcReduzida) ? EstadoEstresse.elevado : EstadoEstresse.calmo;
    }

    final fcElevada = base.fcDesvio > 0 &&
        mediaFcRepousoHoje >= base.fcMedia + margemDesviosSoFc * base.fcDesvio;
    return fcElevada ? EstadoEstresse.elevado : EstadoEstresse.calmo;
  }

  /// `true` quando a detecção de hoje usa as duas métricas (linha de base com VFC e VFC de hoje).
  bool usaVfc({
    required double? mediaVfcRepousoHoje,
    required List<DiaRepouso> historico,
    required DateTime hoje,
  }) {
    final base = linhaDeBase(historico: historico, hoje: hoje);
    return base != null && base.temVfc && mediaVfcRepousoHoje != null;
  }

  List<DiaRepouso> atualizarHistorico({
    required List<DiaRepouso> historicoAtual,
    required DateTime hoje,
    required double? mediaFcRepousoHoje,
    required double? mediaVfcRepousoHoje,
  }) {
    if (mediaFcRepousoHoje == null) return historicoAtual;
    return inserirDia(
      historicoAtual,
      DiaRepouso(
        data: DateTime(hoje.year, hoje.month, hoje.day),
        mediaFcRepouso: mediaFcRepousoHoje,
        mediaVfcRepouso: mediaVfcRepousoHoje,
      ),
    );
  }

  /// Insere (ou substitui) a entrada do dia de [dia] e mantém só os 14 dias mais recentes.
  List<DiaRepouso> inserirDia(List<DiaRepouso> historico, DiaRepouso dia) {
    final semEntradaDoDia = historico.where((d) => !_mesmoDia(d.data, dia.data)).toList();
    final atualizado = [...semEntradaDoDia, dia]..sort((a, b) => a.data.compareTo(b.data));
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
