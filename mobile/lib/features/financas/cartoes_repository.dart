import 'package:dio/dio.dart';
import 'cartao_credito.dart';

class CartoesRepository {
  CartoesRepository(this._dio);

  final Dio _dio;

  Future<List<CartaoCredito>> list() async {
    final response = await _dio.get('/financas/cartoes');
    return (response.data as List)
        .map((json) => CartaoCredito.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<CartaoCredito> create(CartaoCredito cartao) async {
    final response = await _dio.post('/financas/cartoes', data: cartao.toCreateJson());
    return CartaoCredito.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> remove(String id) async {
    await _dio.delete('/financas/cartoes/$id');
  }
}
