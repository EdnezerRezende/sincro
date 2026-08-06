import 'package:dio/dio.dart';
import 'professional.dart';

class ProfessionalsRepository {
  ProfessionalsRepository(this._dio);

  final Dio _dio;

  Future<List<Professional>> search({
    required double lat,
    required double lng,
    List<String> tags = const [],
  }) async {
    final response = await _dio.get('/professionals/search', queryParameters: {
      'lat': lat,
      'lng': lng,
      if (tags.isNotEmpty) 'tags': tags.join(','),
    });
    return (response.data as List)
        .map((json) => Professional.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> listTags() async {
    final response = await _dio.get('/professionals/tags');
    return (response.data as List).map((tag) => tag as String).toList();
  }
}
