import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/compromisso_sugerido.dart';
import 'package:sincro_mobile/features/email_triage/email_reply_repository.dart';

void main() {
  test('gerarRascunhos posts to the right path and parses the response', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'direto': 'a', 'formal': 'b', 'padrao': 'c'},
      ));
    }));

    final repository = EmailReplyRepository(dio);
    final result = await repository.gerarRascunhos('email-1');

    expect(capturedPath, '/resumos-email/email-1/rascunhos');
    expect(result.direto, 'a');
    expect(result.formal, 'b');
    expect(result.padrao, 'c');
  });

  test('enviar posts the texto and parses enviado + compromissoSugerido', () async {
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {
          'enviado': true,
          'compromissoSugerido': {
            'tituloCompromisso': 'Enviar relatório',
            'dataHoraLimite': '2026-09-01T15:00:00',
            'antecedenciaMinutos': 1440,
          },
        },
      ));
    }));

    final repository = EmailReplyRepository(dio);
    final result = await repository.enviar('email-1', 'Envio segunda.');

    expect(capturedData, {'texto': 'Envio segunda.'});
    expect(result.enviado, true);
    expect(result.compromissoSugerido?.tituloCompromisso, 'Enviar relatório');
    expect(result.compromissoSugerido?.antecedenciaMinutos, 1440);
  });

  test('enviar parses a null compromissoSugerido', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'enviado': true, 'compromissoSugerido': null},
      ));
    }));

    final repository = EmailReplyRepository(dio);
    final result = await repository.enviar('email-1', 'Ok.');

    expect(result.compromissoSugerido, isNull);
  });

  test('confirmarCompromisso posts the compromisso as JSON', () async {
    String? capturedPath;
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'agendado': true}));
    }));

    final repository = EmailReplyRepository(dio);
    await repository.confirmarCompromisso(CompromissoSugerido(
      tituloCompromisso: 'Enviar relatório',
      dataHoraLimite: DateTime.parse('2026-09-01T15:00:00'),
      antecedenciaMinutos: 1440,
    ));

    expect(capturedPath, '/resumos-email/compromissos/confirmar');
    final enviado = capturedData as Map<String, dynamic>;
    expect(enviado['tituloCompromisso'], 'Enviar relatório');
    expect(enviado['antecedenciaMinutos'], 1440);

    // A hora de parede é preservada e vem acompanhada de um offset explícito — sem ele o backend
    // resolveria a data no fuso do servidor e criaria o evento no instante errado.
    final dataHoraLimite = enviado['dataHoraLimite'] as String;
    expect(dataHoraLimite, startsWith('2026-09-01T15:00:00.000'));
    expect(
      RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(dataHoraLimite),
      isTrue,
      reason: 'dataHoraLimite precisa carregar o fuso do dispositivo: $dataHoraLimite',
    );
    expect(DateTime.parse(dataHoraLimite).toLocal(), DateTime.parse('2026-09-01T15:00:00'));
  });

  test('confirmarCompromisso serializa um horário UTC com o sufixo Z, sem duplicar offset', () async {
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'agendado': true}));
    }));

    final repository = EmailReplyRepository(dio);
    await repository.confirmarCompromisso(CompromissoSugerido(
      tituloCompromisso: 'Enviar relatório',
      dataHoraLimite: DateTime.utc(2026, 9, 1, 18, 0, 0),
      antecedenciaMinutos: 60,
    ));

    expect((capturedData as Map<String, dynamic>)['dataHoraLimite'], '2026-09-01T18:00:00.000Z');
  });
}
