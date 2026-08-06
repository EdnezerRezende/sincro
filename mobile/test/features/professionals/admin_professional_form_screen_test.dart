import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/admin_professional_form_screen.dart';

DioException _buildDioException({dynamic responseData, int statusCode = 400}) {
  final options = RequestOptions(path: '/admin/professionals');
  return DioException(
    requestOptions: options,
    response: responseData == null
        ? null
        : Response(requestOptions: options, statusCode: statusCode, data: responseData),
  );
}

void main() {
  group('extractServerErrorMessage', () {
    test('returns a string message field as-is', () {
      final e = _buildDioException(responseData: {
        'statusCode': 400,
        'message': 'telefone must start with + followed by the country code and 10-15 digits',
        'error': 'Bad Request',
      });

      expect(
        extractServerErrorMessage(e),
        'telefone must start with + followed by the country code and 10-15 digits',
      );
    });

    test('joins an array message field with "; "', () {
      final e = _buildDioException(responseData: {
        'statusCode': 400,
        'message': ['tags should not be empty', 'bio must be shorter than or equal to 500 characters'],
        'error': 'Bad Request',
      });

      expect(
        extractServerErrorMessage(e),
        'tags should not be empty; bio must be shorter than or equal to 500 characters',
      );
    });

    test('falls back to a generic message when there is no response body', () {
      final e = _buildDioException();

      expect(extractServerErrorMessage(e), 'Não foi possível salvar. Tente novamente.');
    });

    test('falls back to a generic message when the response has no message field', () {
      final e = _buildDioException(responseData: {'statusCode': 500});

      expect(extractServerErrorMessage(e), 'Não foi possível salvar. Tente novamente.');
    });
  });
}
