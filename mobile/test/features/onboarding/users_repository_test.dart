import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/onboarding/users_repository.dart';

void main() {
  test('getMe parses the onboarding status response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter(
      '{"userId":"u1","nome":"Ana","hasSensoryProfile":true,"trustedContactCount":2,"diaRecebimento":5}',
    );
    final repository = UsersRepository(dio);

    final status = await repository.getMe();

    expect(status.userId, 'u1');
    expect(status.nome, 'Ana');
    expect(status.hasSensoryProfile, true);
    expect(status.trustedContactCount, 2);
    expect(status.diaRecebimento, 5);
  });

  test('getMe treats a null diaRecebimento as "not set yet"', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter(
      '{"userId":"u1","nome":"Ana","hasSensoryProfile":false,"trustedContactCount":0,"diaRecebimento":null}',
    );
    final repository = UsersRepository(dio);

    final status = await repository.getMe();

    expect(status.diaRecebimento, isNull);
  });

  test('getMe tolerates a response with no diaRecebimento key at all', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter(
      '{"userId":"u1","nome":"Ana","hasSensoryProfile":false,"trustedContactCount":0}',
    );
    final repository = UsersRepository(dio);

    final status = await repository.getMe();

    expect(status.diaRecebimento, isNull);
  });

  test('getMe parses isAdmin true when present', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter(
      '{"userId":"u1","nome":"Ana","hasSensoryProfile":true,"trustedContactCount":2,"diaRecebimento":5,"isAdmin":true}',
    );
    final repository = UsersRepository(dio);

    final status = await repository.getMe();

    expect(status.isAdmin, true);
  });

  test('getMe defaults isAdmin to false when the key is absent', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter(
      '{"userId":"u1","nome":"Ana","hasSensoryProfile":false,"trustedContactCount":0}',
    );
    final repository = UsersRepository(dio);

    final status = await repository.getMe();

    expect(status.isAdmin, false);
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
