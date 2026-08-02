import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/emergency/emergency_repository.dart';

void main() {
  test('buildMessage posts the contactId and parses the response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {
          'contactId': 'c1',
          'contactName': 'Dra. Marina',
          'whatsapp': '+5511999999999',
          'message': 'Oi Marina, estou passando por um momento difícil agora.',
          'waUrl': 'https://wa.me/5511999999999?text=teste',
        },
      ));
    }));
    final repository = EmergencyRepository(dio);

    final result = await repository.buildMessage('c1');

    expect(result.contactName, 'Dra. Marina');
    expect(result.waUrl, 'https://wa.me/5511999999999?text=teste');
  });
}
