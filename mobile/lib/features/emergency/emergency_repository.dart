import 'package:dio/dio.dart';
import 'emergency_message.dart';

class EmergencyRepository {
  EmergencyRepository(this._dio);

  final Dio _dio;

  Future<EmergencyMessage> buildMessage(String contactId) async {
    final response = await _dio.post('/emergency/message', data: {'contactId': contactId});
    return EmergencyMessage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<EmergencyMessage>> buildMessages(List<String> contactIds, {String? template}) async {
    final response = await _dio.post('/emergency/messages', data: {
      'contactIds': contactIds,
      if (template != null) 'template': template,
    });
    return (response.data as List)
        .map((json) => EmergencyMessage.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
