class FinanceAccountSummary {
  const FinanceAccountSummary({
    required this.id,
    required this.tipo,
    required this.nome,
    required this.saldoOuFatura,
    this.vencimentoFatura,
  });

  final String id;
  final String tipo;
  final String nome;
  final double saldoOuFatura;
  final DateTime? vencimentoFatura;

  factory FinanceAccountSummary.fromJson(Map<String, dynamic> json) {
    return FinanceAccountSummary(
      id: json['id'] as String,
      tipo: json['tipo'] as String,
      nome: json['nome'] as String,
      saldoOuFatura: (json['saldoOuFatura'] as num).toDouble(),
      vencimentoFatura:
          json['vencimentoFatura'] != null ? DateTime.parse(json['vencimentoFatura'] as String) : null,
    );
  }
}

class BoletoSummary {
  const BoletoSummary({required this.id, required this.valor, required this.vencimento});

  final String id;
  final double valor;
  final DateTime vencimento;

  factory BoletoSummary.fromJson(Map<String, dynamic> json) {
    return BoletoSummary(
      id: json['id'] as String,
      valor: (json['valor'] as num).toDouble(),
      vencimento: DateTime.parse(json['vencimento'] as String),
    );
  }
}

class FinanceSummary {
  const FinanceSummary({required this.saldoLivre, required this.contas, required this.boletos});

  final double saldoLivre;
  final List<FinanceAccountSummary> contas;
  final List<BoletoSummary> boletos;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      saldoLivre: (json['saldoLivre'] as num).toDouble(),
      contas: (json['contas'] as List)
          .map((e) => FinanceAccountSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      boletos:
          (json['boletos'] as List).map((e) => BoletoSummary.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
