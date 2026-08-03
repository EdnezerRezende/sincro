class OnboardingStatus {
  const OnboardingStatus({
    required this.userId,
    required this.nome,
    required this.hasSensoryProfile,
    required this.trustedContactCount,
    this.diaRecebimento,
  });

  final String userId;
  final String nome;
  final bool hasSensoryProfile;
  final int trustedContactCount;

  /// Dia do mês em que o usuário costuma receber, ou `null` se ainda não definiu.
  final int? diaRecebimento;

  factory OnboardingStatus.fromJson(Map<String, dynamic> json) {
    return OnboardingStatus(
      userId: json['userId'] as String,
      nome: json['nome'] as String,
      hasSensoryProfile: json['hasSensoryProfile'] as bool,
      trustedContactCount: json['trustedContactCount'] as int,
      diaRecebimento: (json['diaRecebimento'] as num?)?.toInt(),
    );
  }
}
