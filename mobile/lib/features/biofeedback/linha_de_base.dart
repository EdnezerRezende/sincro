/// Linha de base pessoal de repouso: média e desvio-padrão dos dias anteriores do histórico.
///
/// A parte de VFC é opcional — só existe quando dias suficientes do histórico têm variabilidade.
/// Sem ela, a detecção de estresse passa a usar só a frequência cardíaca (ver
/// `BiofeedbackStressDetector.detectar`), e a tela avisa que a variabilidade não está entrando na
/// conta.
class LinhaDeBase {
  const LinhaDeBase({
    required this.dias,
    required this.fcMedia,
    required this.fcDesvio,
    this.vfcMedia,
    this.vfcDesvio,
  });

  /// Dias anteriores (sem contar hoje) que entraram na média.
  final int dias;
  final double fcMedia;
  final double fcDesvio;
  final double? vfcMedia;
  final double? vfcDesvio;

  bool get temVfc => vfcMedia != null && vfcDesvio != null;

  /// Faixa de FC considerada normal: média ± [margemDesvios] desvios.
  ({double minimo, double maximo}) faixaFc(double margemDesvios) => (
        minimo: fcMedia - margemDesvios * fcDesvio,
        maximo: fcMedia + margemDesvios * fcDesvio,
      );

  Map<String, dynamic> toJson() => {
        'dias': dias,
        'fcMedia': fcMedia,
        'fcDesvio': fcDesvio,
        'vfcMedia': vfcMedia,
        'vfcDesvio': vfcDesvio,
      };

  factory LinhaDeBase.fromJson(Map<String, dynamic> json) => LinhaDeBase(
        dias: json['dias'] as int,
        fcMedia: (json['fcMedia'] as num).toDouble(),
        fcDesvio: (json['fcDesvio'] as num).toDouble(),
        vfcMedia: (json['vfcMedia'] as num?)?.toDouble(),
        vfcDesvio: (json['vfcDesvio'] as num?)?.toDouble(),
      );
}
