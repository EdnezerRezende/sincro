import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/email_summary_repository.dart';

void main() {
  test('list parses the array of email summaries', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 's1',
            'remetente': 'Banco <banco@example.com>',
            'assunto': 'Fatura',
            'resumoCurto': 'Fatura vence amanhã',
            'categoria': 'PRECISA_ATENCAO',
            'recebidoEm': '2026-08-02T10:00:00.000Z',
          },
        ],
      ));
    }));
    final repository = EmailSummaryRepository(dio);

    final summaries = await repository.list();

    expect(summaries, hasLength(1));
    expect(summaries.first.assunto, 'Fatura');
    expect(summaries.first.precisaAtencao, true);
  });

  test('conteudo GETs the right path and returns the corpo string', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'corpo': 'Olá, segue o relatório em anexo.', 'ehPreview': false},
      ));
    }));
    final repository = EmailSummaryRepository(dio);

    final corpo = await repository.conteudo('email-1');

    expect(capturedPath, '/resumos-email/email-1/conteudo');
    expect(corpo.corpo, 'Olá, segue o relatório em anexo.');
    expect(corpo.ehPreview, false);
  });

  test('conteudo sinaliza ehPreview quando o backend só tem o snippet curto', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'corpo': 'Trecho curto...', 'ehPreview': true},
      ));
    }));
    final repository = EmailSummaryRepository(dio);

    final corpo = await repository.conteudo('email-1');

    expect(corpo.corpo, 'Trecho curto...');
    expect(corpo.ehPreview, true);
  });

  test('conteudo returns an empty string when corpo is missing from the response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: <String, dynamic>{}));
    }));
    final repository = EmailSummaryRepository(dio);

    final corpo = await repository.conteudo('email-1');

    expect(corpo.corpo, '');
    expect(corpo.ehPreview, false);
  });

  test('arquivar POSTs to the archive endpoint for the given e-mail id', () async {
    String? capturedPath;
    String? capturedMethod;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedMethod = options.method;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'arquivado': true}));
    }));
    final repository = EmailSummaryRepository(dio);

    await repository.arquivar('email-1');

    expect(capturedPath, '/resumos-email/email-1/arquivar');
    expect(capturedMethod, 'POST');
  });

  test('arquivar propagates a 403 (missing gmail.modify scope) instead of swallowing it', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 403,
          data: {'message': 'Reconecte o Gmail para arquivar ou excluir e-mails por aqui.'},
        ),
      ));
    }));
    final repository = EmailSummaryRepository(dio);

    await expectLater(
      repository.arquivar('email-1'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 403)),
    );
  });

  test('excluir POSTs to the trash endpoint for the given e-mail id', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'excluido': true}));
    }));
    final repository = EmailSummaryRepository(dio);

    await repository.excluir('email-1');

    expect(capturedPath, '/resumos-email/email-1/excluir');
  });

  test('excluir propagates a 403 (missing gmail.modify scope) instead of swallowing it', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 403, data: {'message': 'Reconecte o Gmail.'}),
      ));
    }));
    final repository = EmailSummaryRepository(dio);

    await expectLater(
      repository.excluir('email-1'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 403)),
    );
  });
}
