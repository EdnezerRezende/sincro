import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/grounding_cards/admin_grounding_cards_repository.dart';

void main() {
  test('create posts the full card payload', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedData;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data as Map<String, dynamic>;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'id': 'c1'}));
    }));
    final repository = AdminGroundingCardsRepository(dio);

    await repository.create(titulo: 'Respiração 4-7-8', categoria: 'RESPIRACAO', conteudo: 'Inspire...');

    expect(capturedData, {
      'titulo': 'Respiração 4-7-8',
      'categoria': 'RESPIRACAO',
      'conteudo': 'Inspire...',
    });
  });

  test('update patches the card by id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    String? capturedPath;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'id': 'c1'}));
    }));
    final repository = AdminGroundingCardsRepository(dio);

    await repository.update('c1', titulo: 'Novo título', categoria: 'MOVIMENTO', conteudo: 'Novo conteúdo');

    expect(capturedPath, '/admin/grounding-cards/c1');
  });

  test('update includes ativo in the payload when reactivating', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedData;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data as Map<String, dynamic>;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'id': 'c1'}));
    }));
    final repository = AdminGroundingCardsRepository(dio);

    await repository.update('c1', titulo: 'Título', categoria: 'RESPIRACAO', conteudo: 'Conteúdo', ativo: true);

    expect(capturedData!['ativo'], true);
  });

  test('deactivate deletes the card by id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    String? capturedPath;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));
    final repository = AdminGroundingCardsRepository(dio);

    await repository.deactivate('c1');

    expect(capturedPath, '/admin/grounding-cards/c1');
  });

  test('list parses the full card list including inactive ones', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 'c1',
            'titulo': 'Respiração 4-7-8',
            'categoria': 'RESPIRACAO',
            'conteudo': 'Inspire...',
            'ativo': false,
          },
        ],
      ));
    }));
    final repository = AdminGroundingCardsRepository(dio);

    final result = await repository.list();

    expect(result.single.ativo, false);
  });
}
