class AnamneseAnswers {
  const AnamneseAnswers({
    this.toleranciaNotificacao,
    this.gatilhos = const [],
    this.tomPreferido,
  });

  final String? toleranciaNotificacao;
  final List<String> gatilhos;
  final String? tomPreferido;

  AnamneseAnswers copyWith({
    String? toleranciaNotificacao,
    List<String>? gatilhos,
    String? tomPreferido,
  }) {
    return AnamneseAnswers(
      toleranciaNotificacao: toleranciaNotificacao ?? this.toleranciaNotificacao,
      gatilhos: gatilhos ?? this.gatilhos,
      tomPreferido: tomPreferido ?? this.tomPreferido,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'toleranciaNotificacao': toleranciaNotificacao,
      'gatilhos': gatilhos,
      'tomPreferido': tomPreferido,
    };
  }
}
