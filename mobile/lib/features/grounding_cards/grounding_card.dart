const List<String> categoriasCartao = [
  'RESPIRACAO',
  'ATERRAMENTO_SENSORIAL',
  'MOVIMENTO',
  'ATENCAO_PLENA',
  'OUTRO',
];

String rotuloCategoria(String categoria) {
  switch (categoria) {
    case 'RESPIRACAO':
      return 'Respiração';
    case 'ATERRAMENTO_SENSORIAL':
      return 'Aterramento Sensorial';
    case 'MOVIMENTO':
      return 'Movimento/Alongamento';
    case 'ATENCAO_PLENA':
      return 'Atenção Plena';
    default:
      return 'Outro';
  }
}

class GroundingCard {
  const GroundingCard({
    required this.id,
    required this.titulo,
    required this.categoria,
    required this.conteudo,
    required this.ativo,
  });

  final String id;
  final String titulo;
  final String categoria;
  final String conteudo;
  final bool ativo;

  factory GroundingCard.fromJson(Map<String, dynamic> json) {
    return GroundingCard(
      id: json['id'] as String,
      titulo: json['titulo'] as String,
      categoria: json['categoria'] as String,
      conteudo: json['conteudo'] as String,
      ativo: json['ativo'] as bool,
    );
  }
}
