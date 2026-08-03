class EmailSummary {
  const EmailSummary({
    required this.id,
    required this.remetente,
    required this.assunto,
    required this.resumoCurto,
    required this.categoria,
    required this.recebidoEm,
  });

  final String id;
  final String remetente;
  final String assunto;
  final String resumoCurto;
  final String categoria;
  final DateTime recebidoEm;

  bool get precisaAtencao => categoria == 'PRECISA_ATENCAO';

  factory EmailSummary.fromJson(Map<String, dynamic> json) {
    return EmailSummary(
      id: json['id'] as String,
      remetente: json['remetente'] as String,
      assunto: json['assunto'] as String,
      resumoCurto: json['resumoCurto'] as String,
      categoria: json['categoria'] as String,
      recebidoEm: DateTime.parse(json['recebidoEm'] as String),
    );
  }
}
