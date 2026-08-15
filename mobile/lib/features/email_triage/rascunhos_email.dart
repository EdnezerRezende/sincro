class RascunhosEmail {
  const RascunhosEmail({required this.direto, required this.formal, required this.padrao});

  final String direto;
  final String formal;
  final String padrao;

  factory RascunhosEmail.fromJson(Map<String, dynamic> json) {
    return RascunhosEmail(
      direto: json['direto'] as String? ?? '',
      formal: json['formal'] as String? ?? '',
      padrao: json['padrao'] as String? ?? '',
    );
  }
}
