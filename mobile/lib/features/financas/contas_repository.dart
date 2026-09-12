import 'package:dio/dio.dart';
import 'conta_financeira.dart';

class ContasRepository {
  ContasRepository(this._dio);

  final Dio _dio;

  Future<List<ContaFinanceira>> list() async {
    final response = await _dio.get('/financas/contas');
    return (response.data as List)
        .map((json) => ContaFinanceira.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<ContaFinanceira> create(ContaFinanceira conta) async {
    final response = await _dio.post('/financas/contas', data: conta.toCreateJson());
    return ContaFinanceira.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> remove(String id) async {
    await _dio.delete('/financas/contas/$id');
  }
}
