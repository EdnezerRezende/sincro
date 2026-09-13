import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/contas_repository.dart';
import 'package:sincro_mobile/features/financas/conta_financeira.dart';

void main() {
  test('list() GETs /financas/contas and parses the array', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/contas');
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: [
          {'id': 'c1', 'nome': 'Conta corrente', 'tipo': 'CORRENTE', 'saldoAtual': '100.00'},
        ],
      ));
    }));
    final repository = ContasRepository(dio);

    final contas = await repository.list();

    expect(contas, hasLength(1));
    expect(contas.first.nome, 'Conta corrente');
    expect(contas.first.saldoAtual, 100.0);
  });

  test('create() POSTs to /financas/contas with the account payload', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/contas');
      expect(options.data, {'nome': 'Poupança', 'tipo': 'POUPANCA', 'saldoAtual': 50.0});
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 201,
        data: {'id': 'c2', 'nome': 'Poupança', 'tipo': 'POUPANCA', 'saldoAtual': '50.00'},
      ));
    }));
    final repository = ContasRepository(dio);

    final conta = await repository.create(
      const ContaFinanceira(id: '', nome: 'Poupança', tipo: TipoContaFinanceira.poupanca, saldoAtual: 50.0),
    );

    expect(conta.id, 'c2');
  });

  test('remove() DELETEs /financas/contas/:id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/financas/contas/c1');
      expect(options.method, 'DELETE');
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {'removed': true}));
    }));
    final repository = ContasRepository(dio);

    await repository.remove('c1');
  });
}
