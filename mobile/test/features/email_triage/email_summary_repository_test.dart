import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/email_triage/email_summary_repository.dart';

void main() {
  test('list parses the array of email summaries', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {
            'id': 's1',
            'remetente': 'Banco <banco@example.com>',
            'assunto': 'Fatura',
            'resumoCurto': 'Fatura vence amanhã',
            'categoria': 'PRECISA_ATENCAO',
            'recebidoEm': '2026-08-02T10:00:00.000Z',
          },
        ],
      ));
    }));
    final repository = EmailSummaryRepository(dio);

    final summaries = await repository.list();

    expect(summaries, hasLength(1));
    expect(summaries.first.assunto, 'Fatura');
    expect(summaries.first.precisaAtencao, true);
  });
}
