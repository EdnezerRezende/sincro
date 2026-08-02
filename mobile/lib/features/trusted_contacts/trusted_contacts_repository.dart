import 'package:dio/dio.dart';
import 'trusted_contact.dart';

class TrustedContactsRepository {
  TrustedContactsRepository(this._dio);

  final Dio _dio;

  Future<List<TrustedContact>> list() async {
    final response = await _dio.get('/trusted-contacts');
    return (response.data as List)
        .map((json) => TrustedContact.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> create({
    required String nome,
    required String relacao,
    required String whatsapp,
    required int prioridade,
    required bool consentimentoAceito,
  }) async {
    await _dio.post('/trusted-contacts', data: {
      'nome': nome,
      'relacao': relacao,
      'whatsapp': whatsapp,
      'prioridade': prioridade,
      'consentimentoAceito': consentimentoAceito,
    });
  }

  Future<void> remove(String id) async {
    await _dio.delete('/trusted-contacts/$id');
  }
}
