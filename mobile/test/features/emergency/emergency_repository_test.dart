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

  test('buildMessages posts contactIds and template and parses the list', () async {
    Map<String, dynamic>? sentBody;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sentBody = options.data as Map<String, dynamic>;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: [
          {'contactId': 'c1', 'contactName': 'Dra. Marina', 'whatsapp': '+5511999999999', 'message': 'Oi Marina', 'waUrl': 'https://wa.me/1'},
          {'contactId': 'c2', 'contactName': 'João', 'whatsapp': '+5511988880000', 'message': 'Oi João', 'waUrl': 'https://wa.me/2'},
        ],
      ));
    }));
    final repository = EmergencyRepository(dio);

    final result = await repository.buildMessages(['c1', 'c2'], template: 'Oi {primeiro nome}');

    expect(sentBody, {'contactIds': ['c1', 'c2'], 'template': 'Oi {primeiro nome}'});
    expect(result.map((m) => m.contactId), ['c1', 'c2']);
  });

  test('buildMessages omits template when null', () async {
    Map<String, dynamic>? sentBody;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sentBody = options.data as Map<String, dynamic>;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: []));
    }));

    await EmergencyRepository(dio).buildMessages(['c1']);

    expect(sentBody, {'contactIds': ['c1']});
  });
}
