class Professional {
  const Professional({
    required this.id,
    required this.nome,
    required this.tags,
    required this.cidade,
    required this.latitude,
    required this.longitude,
    required this.telefone,
    required this.bio,
    required this.ativo,
    this.distanciaKm,
  });

  final String id;
  final String nome;
  final List<String> tags;
  final String cidade;
  final double latitude;
  final double longitude;
  final String telefone;
  final String bio;
  final bool ativo;

  /// Só vem preenchido quando o profissional veio de uma busca por proximidade
  /// (`GET /professionals/search`); nulo nas telas admin.
  final double? distanciaKm;

  factory Professional.fromJson(Map<String, dynamic> json) {
    return Professional(
      id: json['id'] as String,
      nome: json['nome'] as String,
      tags: (json['tags'] as List).map((t) => t as String).toList(),
      cidade: json['cidade'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      telefone: json['telefone'] as String,
      bio: json['bio'] as String,
      ativo: json['ativo'] as bool,
      distanciaKm: (json['distanciaKm'] as num?)?.toDouble(),
    );
  }
}
