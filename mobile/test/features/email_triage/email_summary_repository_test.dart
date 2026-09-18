import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/email_summary_repository.dart';

/// Adapter falso que substitui o transporte HTTP real de verdade (em vez de um
/// `InterceptorsWrapper` chamando `handler.resolve`, que curto-circuita a validação de status do
/// Dio e faria qualquer teste "aceita 202"/"rejeita 500" passar mesmo se o código de produção
/// não tratasse esses status de jeito nenhum). Com isso, `validateStatus` do Dio roda de verdade:
/// um 5xx vira `DioException`, um 2xx (incluindo 202) vira `Response` normalmente.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._responder);

  final ResponseBody Function(RequestOptions options) _responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _responder(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('list parses the paginated response and returns só os itens', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'itens': [
            {
              'id': 's1',
              'remetente': 'Banco <banco@example.com>',
              'assunto': 'Fatura',
              'resumoCurto': 'Fatura vence amanhã',
              'categoria': 'PRECISA_ATENCAO',
              'recebidoEm': '2026-08-02T10:00:00.000Z',
            },
          ],
          'proximoCursor': null,
        },
      ));
    }));
    final repository = EmailSummaryRepository(dio);

    final summaries = await repository.list();

    expect(summaries, hasLength(1));
    expect(summaries.first.assunto, 'Fatura');
    expect(summaries.first.precisaAtencao, true);
  });

  test('listar manda limite e cursor e devolve a página', () async {
    Map<String, dynamic>? params;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      params = options.queryParameters;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'itens': [
            {
              'id': 's1',
              'remetente': 'Banco <banco@example.com>',
              'assunto': 'Fatura',
              'resumoCurto': 'Fatura vence amanhã',
              'categoria': 'PRECISA_ATENCAO',
              'recebidoEm': '2026-08-02T10:00:00.000Z',
            },
          ],
          'proximoCursor': 'abc',
        },
      ));
    }));

    final pagina = await EmailSummaryRepository(dio).listar(cursor: 'xyz', limite: 20);

    expect(params, {'limite': '20', 'cursor': 'xyz'});
    expect(pagina.itens, hasLength(1));
    expect(pagina.proximoCursor, 'abc');
  });

  test('listar sem cursor não manda o parâmetro', () async {
    Map<String, dynamic>? params;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      params = options.queryParameters;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'itens': <dynamic>[], 'proximoCursor': null},
      ));
    }));

    await EmailSummaryRepository(dio).listar();

    expect(params, {'limite': '50'});
    expect(params!.containsKey('cursor'), false);
  });

  test(
    'listar trata array puro (backend antigo, ainda sem paginação) como página única sem próximo cursor',
    () async {
      // Cenário real: o app mobile já publicado pode falar com um backend que ainda não recebeu o
      // deploy da paginação (`./deploy.sh` não é atômico com a publicação da build mobile) — nesse
      // caso o endpoint devolve o array puro de antes do `{itens, proximoCursor}` existir.
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

      final pagina = await EmailSummaryRepository(dio).listar();

      expect(pagina.itens, hasLength(1));
      expect(pagina.proximoCursor, isNull);
    },
  );

  test('listar trata proximoCursor não-String como null em vez de lançar cast inválido', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'itens': <dynamic>[], 'proximoCursor': 42},
      ));
    }));

    final pagina = await EmailSummaryRepository(dio).listar();

    expect(pagina.itens, isEmpty);
    expect(pagina.proximoCursor, isNull);
  });

  test('listar lança FormatException nomeando o endpoint quando "itens" está ausente', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'proximoCursor': null},
      ));
    }));

    await expectLater(
      EmailSummaryRepository(dio).listar(),
      throwsA(isA<FormatException>().having(
        (e) => e.message,
        'message',
        contains('GET /resumos-email'),
      )),
    );
  });

  test('sincronizar faz POST /resumos-email/sincronizar e aceita 202 (validado pelo Dio de verdade)',
      () async {
    RequestOptions? captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter((options) {
      captured = options;
      return ResponseBody.fromString(
        '{"executado":false,"motivo":"recente"}',
        202,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    await EmailSummaryRepository(dio).sincronizar();

    expect(captured?.path, '/resumos-email/sincronizar');
    expect(captured?.method, 'POST');
  });

  test('sincronizar propaga DioException quando o backend responde 500 (não engole 5xx)', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter((options) {
      return ResponseBody.fromString(
        '{"message":"erro interno"}',
        500,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    await expectLater(
      EmailSummaryRepository(dio).sincronizar(),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 500)),
    );
  });

  test('sincronizar passa receiveTimeout de 120s no POST, maior que o timeout global de 30s',
      () async {
    // A primeira sincronização de uma conta pode varrer ~200 mensagens e classificar cada uma —
    // facilmente ultrapassa o receiveTimeout global de 30s do ApiClient (pensado para chamadas
    // pontuais a um LLM). Este teste garante que o repositório concede o fôlego extra só aqui.
    RequestOptions? captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter((options) {
      captured = options;
      return ResponseBody.fromString(
        '{"executado":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    await EmailSummaryRepository(dio).sincronizar();

    expect(captured?.receiveTimeout, const Duration(seconds: 120));
  });

  test('sincronizar propaga DioException 403 (Gmail não conectado)', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 403,
          data: {'message': 'Gmail não conectado.'},
        ),
      ));
    }));

    await expectLater(
      EmailSummaryRepository(dio).sincronizar(),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 403)),
    );
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
