import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_repository.dart';

void main() {
  test('create posts the contact payload including consent', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedData;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data as Map<String, dynamic>;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'id': 'c1'}));
    }));
    final repository = TrustedContactsRepository(dio);

    await repository.create(
      nome: 'Dra. Marina',
      relacao: 'PSICOLOGO',
      whatsapp: '+5511999999999',
      prioridade: 0,
      consentimentoAceito: true,
    );

    expect(capturedData, {
      'nome': 'Dra. Marina',
      'relacao': 'PSICOLOGO',
      'whatsapp': '+5511999999999',
      'prioridade': 0,
      'consentimentoAceito': true,
    });
  });
}
