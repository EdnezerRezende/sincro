import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/onboarding/users_repository.dart';

void main() {
  test('getMe parses the onboarding status response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAdapter();
    final repository = UsersRepository(dio);

    final status = await repository.getMe();

    expect(status.userId, 'u1');
    expect(status.nome, 'Ana');
    expect(status.hasSensoryProfile, true);
    expect(status.trustedContactCount, 2);
  });
}

class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = '{"userId":"u1","nome":"Ana","hasSensoryProfile":true,"trustedContactCount":2}';
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
