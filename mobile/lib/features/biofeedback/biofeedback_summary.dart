import 'biofeedback_stress_detector.dart';
import 'estado_estresse.dart';
import 'linha_de_base.dart';

class BiofeedbackSummary {
  const BiofeedbackSummary({
    required this.ultimaFc,
    required this.mediaFcHoje,
    required this.mediaVfcHoje,
    required this.estadoEstresse,
    required this.atualizadoEm,
    this.ultimaFcEm,
    this.fcRepousoNativa,
    this.fcRepousoNativaEm,
    this.fcMinHoje,
    this.fcMaxHoje,
    this.linhaDeBase,
    this.usaVfc = false,
  });

  /// Leitura mais recente de FC do dia e o instante em que foi feita — o número que o relógio
  /// mostra como "atual".
  final double? ultimaFc;
  final DateTime? ultimaFcEm;

  /// Média de FC/VFC das leituras em repouso de hoje (as que decidem o estado de estresse).
  final double? mediaFcHoje;
  final double? mediaVfcHoje;

  /// FC em repouso calculada pela própria plataforma (HealthKit / Health Connect) — a mesma que o
  /// relógio exibe como "repouso". Pode ser a de ontem enquanto a de hoje não foi calculada.
  final double? fcRepousoNativa;
  final DateTime? fcRepousoNativaEm;

  /// Mínimo e máximo de FC do dia, inclusive durante atividade.
  final double? fcMinHoje;
  final double? fcMaxHoje;

  /// Linha de base pessoal usada na detecção; `null` enquanto ainda está sendo coletada.
  final LinhaDeBase? linhaDeBase;

  /// `true` quando a detecção de hoje usou VFC além da FC.
  final bool usaVfc;

  final EstadoEstresse estadoEstresse;
  final DateTime atualizadoEm;

  /// Faixa de FC considerada normal, com a MESMA margem que decidiu [estadoEstresse]: 1,5σ quando
  /// a VFC entrou na conta, 2σ quando só a FC decidiu. É o que o gráfico desenha como linha de
  /// base — nunca uma faixa diferente da regra aplicada.
  ({double minimo, double maximo})? get faixaRepousoFc => linhaDeBase?.faixaFc(
        usaVfc
            ? BiofeedbackStressDetector.margemDesvios
            : BiofeedbackStressDetector.margemDesviosSoFc,
      );

  Map<String, dynamic> toJson() => {
        'ultimaFc': ultimaFc,
        'ultimaFcEm': ultimaFcEm?.toIso8601String(),
        'mediaFcHoje': mediaFcHoje,
        'mediaVfcHoje': mediaVfcHoje,
        'fcRepousoNativa': fcRepousoNativa,
        'fcRepousoNativaEm': fcRepousoNativaEm?.toIso8601String(),
        'fcMinHoje': fcMinHoje,
        'fcMaxHoje': fcMaxHoje,
        'linhaDeBase': linhaDeBase?.toJson(),
        'usaVfc': usaVfc,
        'estadoEstresse': estadoEstresse.name,
        'atualizadoEm': atualizadoEm.toIso8601String(),
      };

  factory BiofeedbackSummary.fromJson(Map<String, dynamic> json) {
    DateTime? data(String chave) =>
        json[chave] != null ? DateTime.parse(json[chave] as String) : null;
    return BiofeedbackSummary(
      ultimaFc: (json['ultimaFc'] as num?)?.toDouble(),
      ultimaFcEm: data('ultimaFcEm'),
      mediaFcHoje: (json['mediaFcHoje'] as num?)?.toDouble(),
      mediaVfcHoje: (json['mediaVfcHoje'] as num?)?.toDouble(),
      fcRepousoNativa: (json['fcRepousoNativa'] as num?)?.toDouble(),
      fcRepousoNativaEm: data('fcRepousoNativaEm'),
      fcMinHoje: (json['fcMinHoje'] as num?)?.toDouble(),
      fcMaxHoje: (json['fcMaxHoje'] as num?)?.toDouble(),
      linhaDeBase: json['linhaDeBase'] != null
          ? LinhaDeBase.fromJson(json['linhaDeBase'] as Map<String, dynamic>)
          : null,
      usaVfc: json['usaVfc'] as bool? ?? false,
      // Resumo gravado pela Fase 1 não tem esta chave — tratamos como "ainda coletando dados"
      // em vez de quebrar a leitura de um cache pré-existente. Um valor presente mas
      // desconhecido (cache corrompido, ou gravado por uma versão futura com outros estados)
      // cai no mesmo padrão em vez de lançar: perder o estado de estresse é bem melhor do que
      // deixar o resumo inteiro ilegível.
      estadoEstresse: json['estadoEstresse'] != null
          ? EstadoEstresse.values.firstWhere(
              (e) => e.name == json['estadoEstresse'],
              orElse: () => EstadoEstresse.coletandoDados,
            )
          : EstadoEstresse.coletandoDados,
      atualizadoEm: DateTime.parse(json['atualizadoEm'] as String),
    );
  }
}
