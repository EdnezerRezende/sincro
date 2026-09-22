/// Médias em repouso de um dia, uma entrada da linha de base pessoal.
///
/// [mediaVfcRepouso] é opcional: a variabilidade é medida poucas vezes por dia (em geral de
/// madrugada) e muitos relógios Android nem a gravam no Health Connect. Exigir VFC para registrar
/// o dia deixava a linha de base parada em "0 de 7 dias" para quem só tem frequência cardíaca.
class DiaRepouso {
  const DiaRepouso({
    required this.data,
    required this.mediaFcRepouso,
    this.mediaVfcRepouso,
  });

  final DateTime data;
  final double mediaFcRepouso;
  final double? mediaVfcRepouso;

  Map<String, dynamic> toJson() => {
        'data': data.toIso8601String(),
        'mediaFcRepouso': mediaFcRepouso,
        'mediaVfcRepouso': mediaVfcRepouso,
      };

  factory DiaRepouso.fromJson(Map<String, dynamic> json) {
    return DiaRepouso(
      data: DateTime.parse(json['data'] as String),
      mediaFcRepouso: (json['mediaFcRepouso'] as num).toDouble(),
      mediaVfcRepouso: (json['mediaVfcRepouso'] as num?)?.toDouble(),
    );
  }
}
