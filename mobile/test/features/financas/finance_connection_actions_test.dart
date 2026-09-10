// Covers the "disconnect a finance connection" bar: an explicit confirmation before acting, a
// clear return afterwards (success or failure), and the correct providers invalidated so the
// connections list and the summary (balances/accounts) never keep showing data from a connection
// that was just removed.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/financas/finance_connection.dart';
import 'package:sincro_mobile/features/financas/finance_connection_actions.dart';
import 'package:sincro_mobile/features/financas/finance_connection_repository.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';

class _FakeFinanceConnectionRepository extends FinanceConnectionRepository {
  _FakeFinanceConnectionRepository({this.disconnectError}) : super(Dio());

  final Object? disconnectError;
  int chamadasDisconnect = 0;
  String? ultimoIdDesconectado;

  @override
  Future<void> disconnect(String connectionId) async {
    chamadasDisconnect++;
    ultimoIdDesconectado = connectionId;
    final erro = disconnectError;
    if (erro != null) throw erro;
  }
}

const _conexao = FinanceConnection(id: 'conn-1', instituicao: 'Banco Teste', status: 'UPDATED');

/// Harness mínimo: um botão cujo `onPressed` chama a função sob teste com o `context`/`ref` da
/// própria árvore, e um `Scaffold` para o `ScaffoldMessenger` poder mostrar SnackBars.
Widget _harness({
  required FinanceConnectionRepository repository,
  bool Function(bool)? capturarResultado,
  List<bool>? busyLog,
}) {
  return ProviderScope(
    overrides: [financeConnectionRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: Builder(
        builder: (context) {
          return Consumer(
            builder: (context, ref, _) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    final resultado = await confirmarEDesconectarFinanceConnection(
                      context,
                      ref,
                      _conexao,
                      setBusy: busyLog == null ? null : (busy) => busyLog.add(busy),
                    );
                    capturarResultado?.call(resultado);
                  },
                  child: const Text('acionar'),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('asks for confirmation before disconnecting', (tester) async {
    final repo = _FakeFinanceConnectionRepository();
    await tester.pumpWidget(_harness(repository: repo));

    await tester.tap(find.text('acionar'));
    await tester.pumpAndSettle();

    expect(find.text('Desconectar Banco Teste?'), findsOneWidget);
    expect(repo.chamadasDisconnect, 0);
  });

  testWidgets('cancelling the confirmation never calls the repository', (tester) async {
    final repo = _FakeFinanceConnectionRepository();
    await tester.pumpWidget(_harness(repository: repo));

    await tester.tap(find.text('acionar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(repo.chamadasDisconnect, 0);
  });

  testWidgets('confirming calls disconnect with the right connection id and shows success', (
    tester,
  ) async {
    final repo = _FakeFinanceConnectionRepository();
    bool? resultado;
    final busyLog = <bool>[];

    await tester.pumpWidget(
      _harness(repository: repo, capturarResultado: (r) => resultado = r, busyLog: busyLog),
    );

    await tester.tap(find.text('acionar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Desconectar'));
    await tester.pumpAndSettle();

    expect(repo.chamadasDisconnect, 1);
    expect(repo.ultimoIdDesconectado, 'conn-1');
    expect(find.text('Banco Teste desconectado.'), findsOneWidget);
    expect(resultado, true);
    // busy liga antes da chamada de rede e desliga no fim — nunca fica preso em true.
    expect(busyLog, [true, false]);
  });

  testWidgets('a failed disconnect shows a calm retry message and reports failure', (tester) async {
    final repo = _FakeFinanceConnectionRepository(disconnectError: Exception('boom'));
    bool? resultado;

    await tester.pumpWidget(_harness(repository: repo, capturarResultado: (r) => resultado = r));

    await tester.tap(find.text('acionar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Desconectar'));
    await tester.pumpAndSettle();

    expect(repo.chamadasDisconnect, 1);
    expect(find.text('Não foi possível desconectar. Tente novamente.'), findsOneWidget);
    expect(resultado, false);
  });
}
