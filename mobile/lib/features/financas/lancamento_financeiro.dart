enum TipoLancamento { despesa, receita, faturaCartao }
enum StatusLancamento { pendenteRevisao, confirmado, ignorado }
enum OrigemLancamento { emailParser, manual }

TipoLancamento tipoLancamentoFromJson(String value) {
  switch (value) {
    case 'DESPESA':
      return TipoLancamento.despesa;
    case 'RECEITA':
      return TipoLancamento.receita;
    case 'FATURA_CARTAO':
      return TipoLancamento.faturaCartao;
    default:
      throw ArgumentError('tipo de lançamento desconhecido: $value');
  }
}

StatusLancamento statusLancamentoFromJson(String value) {
  switch (value) {
    case 'PENDENTE_REVISAO':
      return StatusLancamento.pendenteRevisao;
    case 'CONFIRMADO':
      return StatusLancamento.confirmado;
    case 'IGNORADO':
      return StatusLancamento.ignorado;
    default:
      throw ArgumentError('status de lançamento desconhecido: $value');
  }
}

String statusLancamentoToJson(StatusLancamento status) {
  switch (status) {
    case StatusLancamento.pendenteRevisao:
      return 'PENDENTE_REVISAO';
    case StatusLancamento.confirmado:
      return 'CONFIRMADO';
    case StatusLancamento.ignorado:
      return 'IGNORADO';
  }
}

OrigemLancamento origemLancamentoFromJson(String value) {
  switch (value) {
    case 'EMAIL_PARSER':
      return OrigemLancamento.emailParser;
    case 'MANUAL':
      return OrigemLancamento.manual;
    default:
      throw ArgumentError('origem de lançamento desconhecida: $value');
  }
}

class LancamentoFinanceiro {
  const LancamentoFinanceiro({
    required this.id,
    required this.tipo,
    required this.descricao,
    required this.instituicao,
    required this.valor,
    required this.dataVencimento,
    required this.dataCompetencia,
    required this.status,
    required this.origem,
    required this.isPago,
    required this.codigoBarras,
    required this.cartaoId,
    required this.contaId,
  });

  final String id;
  final TipoLancamento tipo;
  final String descricao;
  final String? instituicao;
  final double? valor;
  final DateTime dataVencimento;
  final DateTime dataCompetencia;
  final StatusLancamento status;
  final OrigemLancamento origem;
  final bool isPago;
  final String? codigoBarras;
  final String? cartaoId;
  final String? contaId;

  factory LancamentoFinanceiro.fromJson(Map<String, dynamic> json) {
    final valorRaw = json['valor'] as String?;
    return LancamentoFinanceiro(
      id: json['id'] as String,
      tipo: tipoLancamentoFromJson(json['tipo'] as String),
      descricao: json['descricao'] as String,
      instituicao: json['instituicao'] as String?,
      valor: valorRaw == null ? null : double.parse(valorRaw),
      dataVencimento: DateTime.parse(json['dataVencimento'] as String),
      dataCompetencia: DateTime.parse(json['dataCompetencia'] as String),
      status: statusLancamentoFromJson(json['status'] as String),
      origem: origemLancamentoFromJson(json['origem'] as String),
      isPago: json['isPago'] as bool,
      codigoBarras: json['codigoBarras'] as String?,
      cartaoId: json['cartaoId'] as String?,
      contaId: json['contaId'] as String?,
    );
  }
}
