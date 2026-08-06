import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/admin_professionals_repository.dart';

void main() {
  test('create posts the full professional payload', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedData;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data as Map<String, dynamic>;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'id': 'p1'}));
    }));
    final repository = AdminProfessionalsRepository(dio);

    await repository.create(
      nome: 'Dra. Marina',
      tags: ['TEA'],
      cidade: 'São Paulo',
      latitude: -23.5,
      longitude: -46.6,
      telefone: '+5511999999999',
      bio: 'Bio',
    );

    expect(capturedData, {
      'nome': 'Dra. Marina',
      'tags': ['TEA'],
      'cidade': 'São Paulo',
      'latitude': -23.5,
      'longitude': -46.6,
      'telefone': '+5511999999999',
      'bio': 'Bio',
    });
  });

  test('update patches the professional by id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    String? capturedPath;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'id': 'p1'}));
    }));
    final repository = AdminProfessionalsRepository(dio);

    await repository.update(
      'p1',
      nome: 'Novo nome',
      tags: ['TEA'],
      cidade: 'São Paulo',
      latitude: 0,
      longitude: 0,
      telefone: '+5511999999999',
      bio: 'Bio',
    );

    expect(capturedPath, '/admin/professionals/p1');
  });

  test('deactivate deletes the professional by id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    String? capturedPath;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'success': true}));
    }));
    final repository = AdminProfessionalsRepository(dio);

    await repository.deactivate('p1');

    expect(capturedPath, '/admin/professionals/p1');
  });

  test('list parses the full professional list including inactive ones', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
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
            'ativo': false,
          },
        ],
      ));
    }));
    final repository = AdminProfessionalsRepository(dio);

    final result = await repository.list();

    expect(result.single.ativo, false);
  });
}
