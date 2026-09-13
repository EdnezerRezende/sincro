import 'package:dio/dio.dart';
import 'lancamento_financeiro.dart';

class LancamentosRepository {
  LancamentosRepository(this._dio);

  final Dio _dio;

  Future<List<LancamentoFinanceiro>> list({String? status, String? mes}) async {
    final queryParameters = <String, dynamic>{
      if (status != null) 'status': status,
      if (mes != null) 'mes': mes,
    };
    final response = await _dio.get('/financas/lancamentos', queryParameters: queryParameters);
    return (response.data as List)
        .map((json) => LancamentoFinanceiro.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> confirmar(
    String id, {
    double? valor,
    DateTime? dataVencimento,
    String? contaId,
    String? cartaoId,
  }) async {
    final data = <String, dynamic>{
      if (valor != null) 'valor': valor,
      if (dataVencimento != null) 'dataVencimento': dataVencimento.toIso8601String(),
      if (contaId != null) 'contaId': contaId,
      if (cartaoId != null) 'cartaoId': cartaoId,
    };
    await _dio.patch('/financas/lancamentos/$id/confirmar', data: data);
  }

  Future<void> ignorar(String id) async {
    await _dio.patch('/financas/lancamentos/$id/ignorar');
  }

  Future<LancamentoFinanceiro> create({
    required TipoLancamento tipo,
    required String descricao,
    required DateTime dataVencimento,
    double? valor,
    String? instituicao,
    DateTime? dataCompetencia,
    String? contaId,
    String? cartaoId,
    bool? isPago,
  }) async {
    final data = <String, dynamic>{
      'tipo': tipoLancamentoToJson(tipo),
      'descricao': descricao,
      'dataVencimento': dataVencimento.toIso8601String(),
      if (valor != null) 'valor': valor,
      if (instituicao != null) 'instituicao': instituicao,
      if (dataCompetencia != null) 'dataCompetencia': dataCompetencia.toIso8601String(),
      if (contaId != null) 'contaId': contaId,
      if (cartaoId != null) 'cartaoId': cartaoId,
      if (isPago != null) 'isPago': isPago,
    };
    final response = await _dio.post('/financas/lancamentos', data: data);
    return LancamentoFinanceiro.fromJson(response.data as Map<String, dynamic>);
  }
}
