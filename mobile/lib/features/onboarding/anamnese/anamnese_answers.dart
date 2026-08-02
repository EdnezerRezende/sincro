class AnamneseAnswers {
  const AnamneseAnswers({
    this.toleranciaNotificacao,
    this.gatilhos = const [],
    this.tomPreferido,
    this.outroGatilho,
  });

  final String? toleranciaNotificacao;
  final List<String> gatilhos;
  final String? tomPreferido;
  final String? outroGatilho;

  factory AnamneseAnswers.fromJson(Map<String, dynamic> json) {
    return AnamneseAnswers(
      toleranciaNotificacao: json['toleranciaNotificacao'] as String?,
      gatilhos: (json['gatilhos'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      tomPreferido: json['tomPreferido'] as String?,
      outroGatilho: json['outroGatilho'] as String?,
    );
  }

  AnamneseAnswers copyWith({
    String? toleranciaNotificacao,
    List<String>? gatilhos,
    String? tomPreferido,
    String? outroGatilho,
  }) {
    return AnamneseAnswers(
      toleranciaNotificacao: toleranciaNotificacao ?? this.toleranciaNotificacao,
      gatilhos: gatilhos ?? this.gatilhos,
      tomPreferido: tomPreferido ?? this.tomPreferido,
      outroGatilho: outroGatilho ?? this.outroGatilho,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'toleranciaNotificacao': toleranciaNotificacao,
      'gatilhos': gatilhos,
      'tomPreferido': tomPreferido,
      if (outroGatilho?.isNotEmpty ?? false) 'outroGatilho': outroGatilho,
    };
  }
}
