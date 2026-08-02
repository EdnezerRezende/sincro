import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/sensory_profile_repository.dart';

void main() {
  test('upsert puts the dados payload', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    Map<String, dynamic>? capturedData;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedData = options.data as Map<String, dynamic>;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final repository = SensoryProfileRepository(dio);

    await repository.upsert({'toleranciaNotificacao': 'SILENCIOSAS'});

    expect(capturedData, {
      'dados': {'toleranciaNotificacao': 'SILENCIOSAS'},
    });
  });

  test('remove deletes the sensory profile', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    String? capturedPath;
    String? capturedMethod;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedMethod = options.method;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final repository = SensoryProfileRepository(dio);

    await repository.remove();

    expect(capturedPath, '/sensory-profile');
    expect(capturedMethod, 'DELETE');
  });
}
