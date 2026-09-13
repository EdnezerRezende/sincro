import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_summary_repository.dart';

void main() {
  test('getResumo() GETs /financas/resumo and parses the 5-field shape', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/resumo');
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'saldoLivre': 1234.56,
          'saldoContas': 2000.0,
          'faturasAbertas': 450.0,
          'despesasPendentesCiclo': 300.0,
          'cicloFim': '2026-09-30T00:00:00.000Z',
        },
      ));
    }));
    final repository = FinanceSummaryRepository(dio);

    final resumo = await repository.getResumo();

    expect(resumo.saldoLivre, 1234.56);
  });
}
