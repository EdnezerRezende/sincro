import 'package:dio/dio.dart';

class SensoryProfileRepository {
  SensoryProfileRepository(this._dio);

  final Dio _dio;

  Future<void> upsert(Map<String, dynamic> dados) async {
    await _dio.put('/sensory-profile', data: {'dados': dados});
  }

  Future<void> remove() async {
    await _dio.delete('/sensory-profile');
  }
}
