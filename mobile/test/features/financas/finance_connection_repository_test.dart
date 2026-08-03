import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_connection_repository.dart';

void main() {
  test('createConnectToken posts to /financas/connect-token and returns the token', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'connectToken': 'token-abc'}));
    }));

    final repository = FinanceConnectionRepository(dio);
    final token = await repository.createConnectToken();

    expect(capturedPath, '/financas/connect-token');
    expect(token, 'token-abc');
  });

  test('finalizeConnection posts the itemId and parses the connection', () async {
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'id': 'conn-1', 'instituicao': 'Banco Teste', 'status': 'UPDATED'},
      ));
    }));

    final repository = FinanceConnectionRepository(dio);
    final connection = await repository.finalizeConnection('item-1');

    expect(capturedData, {'itemId': 'item-1'});
    expect(connection.id, 'conn-1');
    expect(connection.instituicao, 'Banco Teste');
  });

  test('listConnections parses a list of connections', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {'id': 'conn-1', 'instituicao': 'Banco Teste', 'status': 'UPDATED'},
        ],
      ));
    }));

    final repository = FinanceConnectionRepository(dio);
    final connections = await repository.listConnections();

    expect(connections, hasLength(1));
    expect(connections.first.instituicao, 'Banco Teste');
  });

  test('disconnect calls the delete endpoint with the connection id', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));

    final repository = FinanceConnectionRepository(dio);
    await repository.disconnect('conn-1');

    expect(capturedPath, '/financas/conexoes/conn-1');
  });
}
