enum TipoContaFinanceira { corrente, carteira, poupanca }

TipoContaFinanceira tipoContaFinanceiraFromJson(String value) {
  switch (value) {
    case 'CORRENTE':
      return TipoContaFinanceira.corrente;
    case 'CARTEIRA':
      return TipoContaFinanceira.carteira;
    case 'POUPANCA':
      return TipoContaFinanceira.poupanca;
    default:
      throw ArgumentError('tipo de conta desconhecido: $value');
  }
}

String tipoContaFinanceiraToJson(TipoContaFinanceira tipo) {
  switch (tipo) {
    case TipoContaFinanceira.corrente:
      return 'CORRENTE';
    case TipoContaFinanceira.carteira:
      return 'CARTEIRA';
    case TipoContaFinanceira.poupanca:
      return 'POUPANCA';
  }
}

class ContaFinanceira {
  const ContaFinanceira({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.saldoAtual,
    this.cor,
  });

  final String id;
  final String nome;
  final TipoContaFinanceira tipo;
  final double saldoAtual;
  final String? cor;

  factory ContaFinanceira.fromJson(Map<String, dynamic> json) {
    return ContaFinanceira(
      id: json['id'] as String,
      nome: json['nome'] as String,
      tipo: tipoContaFinanceiraFromJson(json['tipo'] as String),
      saldoAtual: double.parse(json['saldoAtual'] as String),
      cor: json['cor'] as String?,
    );
  }

  Map<String, dynamic> toCreateJson() => {
        'nome': nome,
        'tipo': tipoContaFinanceiraToJson(tipo),
        'saldoAtual': saldoAtual,
        if (cor != null) 'cor': cor,
      };
}
