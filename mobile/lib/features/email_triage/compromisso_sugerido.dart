class CompromissoSugerido {
  const CompromissoSugerido({
    required this.tituloCompromisso,
    required this.dataHoraLimite,
    required this.antecedenciaMinutos,
  });

  final String tituloCompromisso;
  final DateTime dataHoraLimite;
  final int antecedenciaMinutos;

  factory CompromissoSugerido.fromJson(Map<String, dynamic> json) {
    return CompromissoSugerido(
      tituloCompromisso: json['tituloCompromisso'] as String,
      dataHoraLimite: DateTime.parse(json['dataHoraLimite'] as String),
      antecedenciaMinutos: json['antecedenciaMinutos'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tituloCompromisso': tituloCompromisso,
      'dataHoraLimite': dataHoraLimite.toIso8601String(),
      'antecedenciaMinutos': antecedenciaMinutos,
    };
  }
}
