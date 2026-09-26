import 'package:dio/dio.dart';
import 'onboarding_status.dart';

class UsersRepository {
  UsersRepository(this._dio);

  final Dio _dio;

  Future<void> upsertMe(String nome) async {
    await _dio.post('/users/me', data: {'nome': nome});
  }

  Future<OnboardingStatus> getMe() async {
    final response = await _dio.get('/users/me');
    return OnboardingStatus.fromJson(response.data as Map<String, dynamic>);
  }

  /// Apaga permanentemente a conta e todos os dados do usuário no backend (LGPD art. 18 /
  /// exigência de exclusão de conta da Google Play).
  Future<void> deleteAccount() async {
    await _dio.delete('/users/me');
  }
}
