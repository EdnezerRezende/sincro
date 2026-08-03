class FinanceConnection {
  const FinanceConnection({required this.id, required this.instituicao, required this.status});

  final String id;
  final String instituicao;
  final String status;

  factory FinanceConnection.fromJson(Map<String, dynamic> json) {
    return FinanceConnection(
      id: json['id'] as String,
      instituicao: json['instituicao'] as String,
      status: json['status'] as String,
    );
  }
}
