import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/cartoes_repository.dart';
import 'package:sincro_mobile/features/financas/cartao_credito.dart';

void main() {
  test('list() GETs /financas/cartoes and parses the array', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/cartoes');
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {'id': 'k1', 'nome': 'Nubank', 'diaFechamento': 5, 'diaVencimento': 12, 'limiteTotal': '3000.00'},
        ],
      ));
    }));
    final repository = CartoesRepository(dio);

    final cartoes = await repository.list();

    expect(cartoes, hasLength(1));
    expect(cartoes.first.nome, 'Nubank');
    expect(cartoes.first.limiteTotal, 3000.0);
  });

  test('create() POSTs to /financas/cartoes with the card payload', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/cartoes');
      expect(options.data, {'nome': 'Itaú', 'diaFechamento': 1, 'diaVencimento': 10, 'limiteTotal': 1500.0});
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'id': 'k2', 'nome': 'Itaú', 'diaFechamento': 1, 'diaVencimento': 10, 'limiteTotal': '1500.00'},
      ));
    }));
    final repository = CartoesRepository(dio);

    final cartao = await repository.create(
      const CartaoCredito(id: '', nome: 'Itaú', diaFechamento: 1, diaVencimento: 10, limiteTotal: 1500.0),
    );

    expect(cartao.id, 'k2');
  });

  test('remove() DELETEs /financas/cartoes/:id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/cartoes/k1');
      expect(options.method, 'DELETE');
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'removed': true}));
    }));
    final repository = CartoesRepository(dio);

    await repository.remove('k1');
  });
}
