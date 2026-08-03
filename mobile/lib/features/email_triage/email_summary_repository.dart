import 'package:dio/dio.dart';
import 'email_summary.dart';

class EmailSummaryRepository {
  EmailSummaryRepository(this._dio);

  final Dio _dio;

  Future<List<EmailSummary>> list() async {
    final response = await _dio.get('/resumos-email');
    final data = response.data as List<dynamic>;
    return data.map((json) => EmailSummary.fromJson(json as Map<String, dynamic>)).toList();
  }
}
