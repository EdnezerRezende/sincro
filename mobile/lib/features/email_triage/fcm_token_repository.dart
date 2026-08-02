import 'package:dio/dio.dart';

class FcmTokenRepository {
  FcmTokenRepository(this._dio);

  final Dio _dio;

  Future<void> register(String fcmToken) async {
    await _dio.post('/users/me/fcm-token', data: {'fcmToken': fcmToken});
  }
}
