import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_cards_repository.dart';

void main() {
  test('list sends categoria as a query parameter when given', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedQuery;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedQuery = options.queryParameters;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 'c1',
            'titulo': 'Respiração 4-7-8',
            'categoria': 'RESPIRACAO',
            'conteudo': 'Inspire...',
            'ativo': true,
          },
        ],
      ));
    }));
    final repository = GroundingCardsRepository(dio);

    final result = await repository.list(categoria: 'RESPIRACAO');

    expect(capturedQuery, {'categoria': 'RESPIRACAO'});
    expect(result.single.titulo, 'Respiração 4-7-8');
  });

  test('list omits categoria when none is given', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedQuery;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedQuery = options.queryParameters;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: []));
    }));
    final repository = GroundingCardsRepository(dio);

    await repository.list();

    expect(capturedQuery!.containsKey('categoria'), false);
  });

  test('listFavoritos parses the favorited cards', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    String? capturedPath;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {'id': 'c1', 'titulo': 'Respiração 4-7-8', 'categoria': 'RESPIRACAO', 'conteudo': 'Inspire...', 'ativo': true},
        ],
      ));
    }));
    final repository = GroundingCardsRepository(dio);

    final result = await repository.listFavoritos();

    expect(capturedPath, '/grounding-cards/favoritos');
    expect(result.single.id, 'c1');
  });

  test('favoritar posts to the favoritar endpoint for the given card id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    String? capturedPath;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'success': true}));
    }));
    final repository = GroundingCardsRepository(dio);

    await repository.favoritar('c1');

    expect(capturedPath, '/grounding-cards/c1/favoritar');
  });

  test('desfavoritar deletes the favoritar endpoint for the given card id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    String? capturedPath;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));
    final repository = GroundingCardsRepository(dio);

    await repository.desfavoritar('c1');

    expect(capturedPath, '/grounding-cards/c1/favoritar');
  });
}
