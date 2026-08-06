import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/professionals_repository.dart';

void main() {
  test('search sends lat/lng and joined tags as query parameters', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedQuery;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedQuery = options.queryParameters;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 'p1',
            'nome': 'Dra. Marina',
            'tags': ['TEA'],
            'cidade': 'São Paulo',
            'latitude': -23.5,
            'longitude': -46.6,
            'telefone': '+5511999999999',
            'bio': 'Bio',
            'ativo': true,
            'distanciaKm': 3.2,
          },
        ],
      ));
    }));
    final repository = ProfessionalsRepository(dio);

    final result = await repository.search(lat: -23.5, lng: -46.6, tags: ['TEA', 'TDAH']);

    expect(capturedQuery, {'lat': -23.5, 'lng': -46.6, 'tags': 'TEA,TDAH'});
    expect(result.single.nome, 'Dra. Marina');
    expect(result.single.distanciaKm, 3.2);
  });

  test('search omits the tags query parameter when none are selected', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedQuery;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedQuery = options.queryParameters;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: []));
    }));
    final repository = ProfessionalsRepository(dio);

    await repository.search(lat: 0, lng: 0);

    expect(capturedQuery!.containsKey('tags'), false);
  });

  test('listTags parses a list of strings', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: ['TEA', 'TDAH']));
    }));
    final repository = ProfessionalsRepository(dio);

    final tags = await repository.listTags();

    expect(tags, ['TEA', 'TDAH']);
  });
}
