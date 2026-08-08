import 'package:dio/dio.dart';
import 'grounding_card.dart';

class AdminGroundingCardsRepository {
  AdminGroundingCardsRepository(this._dio);

  final Dio _dio;

  Future<List<GroundingCard>> list() async {
    final response = await _dio.get('/admin/grounding-cards');
    return (response.data as List)
        .map((json) => GroundingCard.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> create({required String titulo, required String categoria, required String conteudo}) async {
    await _dio.post('/admin/grounding-cards', data: {
      'titulo': titulo,
      'categoria': categoria,
      'conteudo': conteudo,
    });
  }

  Future<void> update(
    String id, {
    required String titulo,
    required String categoria,
    required String conteudo,
    bool? ativo,
  }) async {
    await _dio.patch('/admin/grounding-cards/$id', data: {
      'titulo': titulo,
      'categoria': categoria,
      'conteudo': conteudo,
      if (ativo != null) 'ativo': ativo,
    });
  }

  Future<void> deactivate(String id) async {
    await _dio.delete('/admin/grounding-cards/$id');
  }
}
