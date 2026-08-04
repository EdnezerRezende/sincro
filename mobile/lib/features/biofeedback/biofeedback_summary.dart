import 'estado_estresse.dart';

class BiofeedbackSummary {
  const BiofeedbackSummary({
    required this.ultimaFc,
    required this.mediaFcHoje,
    required this.mediaVfcHoje,
    required this.estadoEstresse,
    required this.atualizadoEm,
  });

  final double? ultimaFc;
  final double? mediaFcHoje;
  final double? mediaVfcHoje;
  final EstadoEstresse estadoEstresse;
  final DateTime atualizadoEm;

  Map<String, dynamic> toJson() => {
        'ultimaFc': ultimaFc,
        'mediaFcHoje': mediaFcHoje,
        'mediaVfcHoje': mediaVfcHoje,
        'estadoEstresse': estadoEstresse.name,
        'atualizadoEm': atualizadoEm.toIso8601String(),
      };

  factory BiofeedbackSummary.fromJson(Map<String, dynamic> json) {
    return BiofeedbackSummary(
      ultimaFc: (json['ultimaFc'] as num?)?.toDouble(),
      mediaFcHoje: (json['mediaFcHoje'] as num?)?.toDouble(),
      mediaVfcHoje: (json['mediaVfcHoje'] as num?)?.toDouble(),
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
