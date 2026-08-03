import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/dia_recebimento_repository.dart';

void main() {
  test('update sends the chosen day to the backend', () async {
    String? capturedPath;
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));

    final repository = DiaRecebimentoRepository(dio);
    await repository.update(15);

    expect(capturedPath, '/users/me/dia-recebimento');
    expect(capturedData, {'diaRecebimento': 15});
  });

  test('update sends null to clear the day', () async {
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));

    final repository = DiaRecebimentoRepository(dio);
    await repository.update(null);

    expect(capturedData, {'diaRecebimento': null});
  });
}
