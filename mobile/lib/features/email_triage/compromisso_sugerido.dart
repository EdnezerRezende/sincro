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
      'dataHoraLimite': iso8601ComFuso(dataHoraLimite),
      'antecedenciaMinutos': antecedenciaMinutos,
    };
  }
}

/// `DateTime.toIso8601String()` só inclui o fuso quando o valor é UTC ("Z"); para um horário local
/// ele devolve uma string ingênua, sem offset. Enviar essa string ingênua faz o backend resolvê-la
/// no fuso do SERVIDOR, criando o evento no instante errado (um "15h" brasileiro virava 12h BRT em
/// servidor UTC). Aqui o offset do dispositivo é anexado explicitamente.
String iso8601ComFuso(DateTime dataHora) {
  if (dataHora.isUtc) return dataHora.toIso8601String(); // já termina em "Z"
  final offset = dataHora.timeZoneOffset;
  final sinal = offset.isNegative ? '-' : '+';
  final horas = offset.inHours.abs().toString().padLeft(2, '0');
  final minutos = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${dataHora.toIso8601String()}$sinal$horas:$minutos';
}
