class FinanceSummary {
  const FinanceSummary({
    required this.saldoLivre,
    required this.saldoContas,
    required this.faturasAbertas,
    required this.despesasPendentesCiclo,
    required this.cicloFim,
  });

  final double saldoLivre;
  final double saldoContas;
  final double faturasAbertas;
  final double despesasPendentesCiclo;
  final DateTime cicloFim;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      saldoLivre: (json['saldoLivre'] as num).toDouble(),
      saldoContas: (json['saldoContas'] as num).toDouble(),
      faturasAbertas: (json['faturasAbertas'] as num).toDouble(),
      despesasPendentesCiclo: (json['despesasPendentesCiclo'] as num).toDouble(),
      cicloFim: DateTime.parse(json['cicloFim'] as String),
    );
  }
}
