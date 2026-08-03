import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_summary_repository.dart';

void main() {
  test('getResumo parses saldo livre, contas, and boletos', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'saldoLivre': 1400.0,
          'fimCiclo': '2026-08-31T00:00:00.000Z',
          'contas': [
            {
              'id': 'acc-1',
              'tipo': 'CORRENTE',
              'nome': 'Conta Corrente',
              'saldoOuFatura': 2000.0,
              'vencimentoFatura': null,
            },
          ],
          'boletos': [
            {'id': 'boleto-1', 'valor': 100.0, 'vencimento': '2026-08-05T00:00:00.000Z'},
          ],
        },
      ));
    }));

    final repository = FinanceSummaryRepository(dio);
    final summary = await repository.getResumo();

    expect(summary.saldoLivre, 1400.0);
    expect(summary.contas, hasLength(1));
    expect(summary.contas.first.nome, 'Conta Corrente');
    expect(summary.boletos, hasLength(1));
    expect(summary.boletos.first.valor, 100.0);
  });

  test('sync posts to /financas/sync', () async {
    String? capturedPath;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      capturedPath = options.path;
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {'success': true}));
    }));

    final repository = FinanceSummaryRepository(dio);
    await repository.sync();

    expect(capturedPath, '/financas/sync');
  });
}
