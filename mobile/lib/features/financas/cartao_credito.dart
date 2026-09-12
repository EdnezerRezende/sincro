class CartaoCredito {
  const CartaoCredito({
    required this.id,
    required this.nome,
    required this.diaFechamento,
    required this.diaVencimento,
    required this.limiteTotal,
    this.cor,
  });

  final String id;
  final String nome;
  final int diaFechamento;
  final int diaVencimento;
  final double limiteTotal;
  final String? cor;

  factory CartaoCredito.fromJson(Map<String, dynamic> json) {
    return CartaoCredito(
      id: json['id'] as String,
      nome: json['nome'] as String,
      diaFechamento: json['diaFechamento'] as int,
      diaVencimento: json['diaVencimento'] as int,
      limiteTotal: double.parse(json['limiteTotal'] as String),
      cor: json['cor'] as String?,
    );
  }

  Map<String, dynamic> toCreateJson() => {
        'nome': nome,
        'diaFechamento': diaFechamento,
        'diaVencimento': diaVencimento,
        'limiteTotal': limiteTotal,
        if (cor != null) 'cor': cor,
      };
}
