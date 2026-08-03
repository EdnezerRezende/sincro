import 'package:dio/dio.dart';
import 'finance_connection.dart';

class FinanceConnectionRepository {
  FinanceConnectionRepository(this._dio);

  final Dio _dio;

  Future<String> createConnectToken() async {
    final response = await _dio.post('/financas/connect-token');
    return (response.data as Map<String, dynamic>)['connectToken'] as String;
  }

  Future<FinanceConnection> finalizeConnection(String itemId) async {
    final response = await _dio.post('/financas/conexoes', data: {'itemId': itemId});
    return FinanceConnection.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<FinanceConnection>> listConnections() async {
    final response = await _dio.get('/financas/conexoes');
    return (response.data as List)
        .map((e) => FinanceConnection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> disconnect(String connectionId) async {
    await _dio.delete('/financas/conexoes/$connectionId');
  }
}
