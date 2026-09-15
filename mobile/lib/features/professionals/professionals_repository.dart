import 'package:dio/dio.dart';
import 'professional.dart';

class ProfessionalsRepository {
  ProfessionalsRepository(this._dio);

  final Dio _dio;

  Future<List<Professional>> search({
    required double lat,
    required double lng,
    List<String> tags = const [],
    String? q,
  }) async {
    final termo = q?.trim() ?? '';
    final response = await _dio.get('/professionals/search', queryParameters: {
      'lat': lat,
      'lng': lng,
      if (tags.isNotEmpty) 'tags': tags.join(','),
      if (termo.isNotEmpty) 'q': termo,
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
