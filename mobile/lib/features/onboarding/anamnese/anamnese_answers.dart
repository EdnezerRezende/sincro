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
