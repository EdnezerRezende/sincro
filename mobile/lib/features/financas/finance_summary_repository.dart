import 'package:dio/dio.dart';
import 'finance_summary.dart';

class FinanceSummaryRepository {
  FinanceSummaryRepository(this._dio);

  final Dio _dio;

  Future<FinanceSummary> getResumo() async {
    final response = await _dio.get('/financas/resumo');
    return FinanceSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> sync() async {
    await _dio.post('/financas/sync');
  }
}
