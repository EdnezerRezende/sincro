class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.nome,
    required this.relacao,
    required this.whatsapp,
    required this.prioridade,
  });

  final String id;
  final String nome;
  final String relacao;
  final String whatsapp;
  final int prioridade;

  factory TrustedContact.fromJson(Map<String, dynamic> json) {
    return TrustedContact(
      id: json['id'] as String,
      nome: json['nome'] as String,
      relacao: json['relacao'] as String,
      whatsapp: json['whatsapp'] as String,
      prioridade: json['prioridade'] as int,
    );
  }
}
