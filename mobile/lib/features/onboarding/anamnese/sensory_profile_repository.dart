import 'package:dio/dio.dart';

class SensoryProfileRepository {
  SensoryProfileRepository(this._dio);

  final Dio _dio;

  Future<void> upsert(Map<String, dynamic> dados) async {
    await _dio.put('/sensory-profile', data: {'dados': dados});
  }

  /// Returns the previously saved `dados` blob, or null if the user has no
  /// sensory profile yet (e.g. `GET /sensory-profile` responds with `null`).
  Future<Map<String, dynamic>?> get() async {
    final response = await _dio.get('/sensory-profile');
    final data = response.data;
    if (data == null) return null;
    final dados = (data as Map<String, dynamic>)['dados'];
    if (dados == null) return null;
    return dados as Map<String, dynamic>;
  }

  Future<void> remove() async {
    await _dio.delete('/sensory-profile');
  }
}
