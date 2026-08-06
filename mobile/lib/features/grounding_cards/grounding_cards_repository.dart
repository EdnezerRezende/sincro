import 'package:dio/dio.dart';
import 'grounding_card.dart';

class GroundingCardsRepository {
  GroundingCardsRepository(this._dio);

  final Dio _dio;

  Future<List<GroundingCard>> list({String? categoria}) async {
    final response = await _dio.get('/grounding-cards', queryParameters: {
      if (categoria != null) 'categoria': categoria,
    });
    return (response.data as List)
        .map((json) => GroundingCard.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<GroundingCard>> listFavoritos() async {
    final response = await _dio.get('/grounding-cards/favoritos');
    return (response.data as List)
        .map((json) => GroundingCard.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> favoritar(String id) async {
    await _dio.post('/grounding-cards/$id/favoritar');
  }

  Future<void> desfavoritar(String id) async {
    await _dio.delete('/grounding-cards/$id/favoritar');
  }
}
