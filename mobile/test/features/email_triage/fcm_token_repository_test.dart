import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/fcm_token_repository.dart';

void main() {
  test('register posts the fcm token', () async {
    String? capturedPath;
    Object? capturedData;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      capturedData = options.data;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'success': true}));
    }));
    final repository = FcmTokenRepository(dio);

    await repository.register('device-token-abc');

    expect(capturedPath, '/users/me/fcm-token');
    expect(capturedData, {'fcmToken': 'device-token-abc'});
  });
}
