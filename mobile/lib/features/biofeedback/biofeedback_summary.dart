class BiofeedbackSummary {
  const BiofeedbackSummary({
    required this.ultimaFc,
    required this.mediaFcHoje,
    required this.mediaVfcHoje,
    required this.atualizadoEm,
  });

  final double? ultimaFc;
  final double? mediaFcHoje;
  final double? mediaVfcHoje;
  final DateTime atualizadoEm;

  Map<String, dynamic> toJson() => {
        'ultimaFc': ultimaFc,
        'mediaFcHoje': mediaFcHoje,
        'mediaVfcHoje': mediaVfcHoje,
        'atualizadoEm': atualizadoEm.toIso8601String(),
      };

  factory BiofeedbackSummary.fromJson(Map<String, dynamic> json) {
    return BiofeedbackSummary(
      ultimaFc: (json['ultimaFc'] as num?)?.toDouble(),
      mediaFcHoje: (json['mediaFcHoje'] as num?)?.toDouble(),
      mediaVfcHoje: (json['mediaVfcHoje'] as num?)?.toDouble(),
      atualizadoEm: DateTime.parse(json['atualizadoEm'] as String),
    );
  }
}
