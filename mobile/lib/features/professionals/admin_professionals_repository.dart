import 'package:dio/dio.dart';
import 'professional.dart';

class AdminProfessionalsRepository {
  AdminProfessionalsRepository(this._dio);

  final Dio _dio;

  Future<List<Professional>> list() async {
    final response = await _dio.get('/admin/professionals');
    return (response.data as List)
        .map((json) => Professional.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> create({
    required String nome,
    required List<String> tags,
    required String cidade,
    required double latitude,
    required double longitude,
    required String telefone,
    required String bio,
  }) async {
    await _dio.post('/admin/professionals', data: {
      'nome': nome,
      'tags': tags,
      'cidade': cidade,
      'latitude': latitude,
      'longitude': longitude,
      'telefone': telefone,
      'bio': bio,
    });
  }

  Future<void> update(
    String id, {
    required String nome,
    required List<String> tags,
    required String cidade,
    required double latitude,
    required double longitude,
    required String telefone,
    required String bio,
  }) async {
    await _dio.patch('/admin/professionals/$id', data: {
      'nome': nome,
      'tags': tags,
      'cidade': cidade,
      'latitude': latitude,
      'longitude': longitude,
      'telefone': telefone,
      'bio': bio,
    });
  }

  Future<void> deactivate(String id) async {
    await _dio.delete('/admin/professionals/$id');
  }
}
