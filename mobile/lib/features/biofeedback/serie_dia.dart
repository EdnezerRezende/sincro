import 'health_reading.dart';

/// Um bloco de 5 minutos da série de frequência cardíaca do dia.
///
/// O relógio pode gravar uma leitura a cada poucos segundos durante um treino — milhares por dia.
/// Guardar tudo no cache e desenhar ponto a ponto seria caro e ilegível; agregar em blocos fixos
/// limita a série a 288 pontos e ainda preserva o que interessa: a média (a linha), o mínimo e o
/// máximo (o pico e o vale reais, não os da média).
class PontoSerieDia {
  const PontoSerieDia({
    required this.inicio,
    required this.media,
    required this.minimo,
    required this.maximo,
    required this.emRepouso,
  });

  /// Início do bloco, em hora local, alinhado a múltiplos de 5 minutos.
  final DateTime inicio;
  final double media;
  final double minimo;
  final double maximo;

  /// `true` só quando todas as leituras do bloco foram feitas em repouso (ver
  /// `BiofeedbackStressDetector.emRepouso`). Um bloco com qualquer movimento conta como atividade,
  /// para o gráfico nunca pintar um trecho de caminhada como se fosse repouso.
  final bool emRepouso;

  Map<String, dynamic> toJson() => {
        't': inicio.toIso8601String(),
        'm': media,
        'lo': minimo,
        'hi': maximo,
        'r': emRepouso,
      };

  factory PontoSerieDia.fromJson(Map<String, dynamic> json) => PontoSerieDia(
        inicio: DateTime.parse(json['t'] as String),
        media: (json['m'] as num).toDouble(),
        minimo: (json['lo'] as num).toDouble(),
        maximo: (json['hi'] as num).toDouble(),
        emRepouso: json['r'] as bool,
      );
}

/// Série de frequência cardíaca de um dia, agregada em blocos de 5 minutos e ordenada no tempo.
class SerieDia {
  const SerieDia({required this.dia, required this.pontos});

  static const duracaoBloco = Duration(minutes: 5);

  /// Meia-noite local do dia a que a série se refere.
  final DateTime dia;
  final List<PontoSerieDia> pontos;

  bool get vazia => pontos.isEmpty;

  /// Bloco com o maior máximo do dia (o primeiro, em caso de empate).
  PontoSerieDia? get pico =>
      vazia ? null : pontos.reduce((a, b) => b.maximo > a.maximo ? b : a);

  /// Bloco com o menor mínimo do dia (o primeiro, em caso de empate).
  PontoSerieDia? get vale =>
      vazia ? null : pontos.reduce((a, b) => b.minimo < a.minimo ? b : a);

  PontoSerieDia? get ultimo => vazia ? null : pontos.last;

  double? get minimo => vale?.minimo;
  double? get maximo => pico?.maximo;

  /// Agrega [leituras] do dia [dia] (meia-noite local). Leituras de outros dias são ignoradas.
  factory SerieDia.agregar({
    required DateTime dia,
    required List<HealthReading> leituras,
    required bool Function(DateTime timestamp) emRepouso,
  }) {
    final inicioDoDia = DateTime(dia.year, dia.month, dia.day);
    // Calendário, não `Duration(days: 1)`: no dia de mudança de horário de verão o dia tem 23 ou 25 h.
    final fimDoDia = DateTime(dia.year, dia.month, dia.day + 1);
    final blocos = <int, List<HealthReading>>{};
    for (final leitura in leituras) {
      final t = leitura.timestamp;
      if (t.isBefore(inicioDoDia) || !t.isBefore(fimDoDia)) continue;
      final indice = t.difference(inicioDoDia).inMinutes ~/ duracaoBloco.inMinutes;
      blocos.putIfAbsent(indice, () => []).add(leitura);
    }
    final indices = blocos.keys.toList()..sort();
    final pontos = indices.map((indice) {
      final grupo = blocos[indice]!;
      final valores = grupo.map((l) => l.valor);
      return PontoSerieDia(
        inicio: inicioDoDia.add(duracaoBloco * indice),
        media: valores.reduce((a, b) => a + b) / grupo.length,
        minimo: valores.reduce((a, b) => a < b ? a : b),
        maximo: valores.reduce((a, b) => a > b ? a : b),
        emRepouso: grupo.every((l) => emRepouso(l.timestamp)),
      );
    }).toList();
    return SerieDia(dia: inicioDoDia, pontos: pontos);
  }

  Map<String, dynamic> toJson() => {
        'dia': dia.toIso8601String(),
        'pontos': pontos.map((p) => p.toJson()).toList(),
      };

  factory SerieDia.fromJson(Map<String, dynamic> json) => SerieDia(
        dia: DateTime.parse(json['dia'] as String),
        pontos: (json['pontos'] as List<dynamic>)
            .map((e) => PontoSerieDia.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
