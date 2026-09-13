import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/lancamentos_repository.dart';

void main() {
  test('list() GETs /financas/lancamentos with status and mes query params', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/lancamentos');
      expect(options.queryParameters, {'status': 'PENDENTE_REVISAO', 'mes': '2026-09'});
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 'l1', 'tipo': 'DESPESA', 'descricao': 'Conta de luz', 'instituicao': 'Enel',
            'valor': '150.30', 'dataVencimento': '2026-09-15T00:00:00.000Z',
            'dataCompetencia': '2026-09-15T00:00:00.000Z', 'status': 'PENDENTE_REVISAO',
            'origem': 'EMAIL_PARSER', 'isPago': false, 'codigoBarras': null,
            'cartaoId': null, 'contaId': null,
          },
        ],
      ));
    }));
    final repository = LancamentosRepository(dio);

    final lancamentos = await repository.list(status: 'PENDENTE_REVISAO', mes: '2026-09');

    expect(lancamentos, hasLength(1));
    expect(lancamentos.first.descricao, 'Conta de luz');
  });

  test('list() omits absent query params entirely', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.queryParameters, isEmpty);
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: <dynamic>[]));
    }));
    final repository = LancamentosRepository(dio);

    await repository.list();
  });

  test('confirmar() PATCHes /financas/lancamentos/:id/confirmar with only the provided fields', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/lancamentos/l1/confirmar');
      expect(options.method, 'PATCH');
      expect(options.data, {'valor': 512.40});
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final repository = LancamentosRepository(dio);

    await repository.confirmar('l1', valor: 512.40);
  });

  test('ignorar() PATCHes /financas/lancamentos/:id/ignorar with no body', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/lancamentos/l1/ignorar');
      expect(options.method, 'PATCH');
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final repository = LancamentosRepository(dio);

    await repository.ignorar('l1');
  });
}
