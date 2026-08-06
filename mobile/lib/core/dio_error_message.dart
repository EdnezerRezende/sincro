import 'package:dio/dio.dart';

/// Extracts a human-readable message from a Nest validation-error response
/// shaped as `{ statusCode, message, error }`, where `message` may be a
/// string or an array of strings.
String extractServerErrorMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    final message = data['message'];
    if (message is List) {
      final joined = message.map((m) => m.toString()).join('; ');
      if (joined.isNotEmpty) return joined;
    } else if (message is String && message.isNotEmpty) {
      return message;
    }
  }
  return 'Não foi possível salvar. Tente novamente.';
}
