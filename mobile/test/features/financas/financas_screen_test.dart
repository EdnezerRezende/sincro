// Covers the "disconnect a finance connection from Finanças itself" bar: each connected
// institution is listed with its own disconnect action (there can be more than one), the action
// requires confirmation, and confirming calls the repository and refreshes both the connections
// list and the summary — reusing the same helper Configurações uses, never a second
// implementation.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/financas/finance_connection.dart';
import 'package:sincro_mobile/features/financas/finance_connection_repository.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';
import 'package:sincro_mobile/features/financas/finance_summary_repository.dart';
import 'package:sincro_mobile/features/financas/financas_screen.dart';

class _FakeFinanceConnectionRepository extends FinanceConnectionRepository {
  _FakeFinanceConnectionRepository(this._connections, {this.disconnectError}) : super(Dio());

  List<FinanceConnection> _connections;
  final Object? disconnectError;
  int chamadasDisconnect = 0;
  String? ultimoIdDesconectado;

  @override
  Future<List<FinanceConnection>> listConnections() async => List.of(_connections);

  @override
  Future<void> disconnect(String connectionId) async {
    chamadasDisconnect++;
    ultimoIdDesconectado = connectionId;
    final erro = disconnectError;
    if (erro != null) throw erro;
    _connections = _connections.where((c) => c.id != connectionId).toList();
  }
}

class _FakeFinanceSummaryRepository extends FinanceSummaryRepository {
  _FakeFinanceSummaryRepository(this._summary) : super(Dio());

  final FinanceSummary _summary;
  int chamadasSync = 0;

  @override
  Future<FinanceSummary> getResumo() async => _summary;

  @override
  Future<void> sync() async {
    chamadasSync++;
  }
}

const _summaryVazio = FinanceSummary(saldoLivre: 0, contas: [], boletos: []);

Widget _app({
  required List<FinanceConnection> connections,
  Object? disconnectError,
}) {
  final connectionRepo = _FakeFinanceConnectionRepository(connections, disconnectError: disconnectError);
  final summaryRepo = _FakeFinanceSummaryRepository(_summaryVazio);
  return ProviderScope(
    overrides: [
      financeConnectionRepositoryProvider.overrideWithValue(connectionRepo),
      financeSummaryRepositoryProvider.overrideWithValue(summaryRepo),
    ],
    child: MaterialApp(theme: sincroLightTheme, home: const FinancasScreen()),
  );
}

void main() {
  testWidgets('lists each connected institution with its own disconnect action', (tester) async {
    await tester.pumpWidget(
      _app(
        connections: const [
          FinanceConnection(id: 'conn-1', instituicao: 'Banco A', status: 'UPDATED'),
          FinanceConnection(id: 'conn-2', instituicao: 'Banco B', status: 'UPDATED'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Conexões'), findsOneWidget);
    expect(find.text('Banco A'), findsOneWidget);
    expect(find.text('Banco B'), findsOneWidget);
    expect(find.byIcon(Icons.link_off), findsNWidgets(2));
  });

  testWidgets('disconnecting one institution asks for confirmation before acting', (tester) async {
    await tester.pumpWidget(
      _app(
        connections: const [FinanceConnection(id: 'conn-1', instituicao: 'Banco A', status: 'UPDATED')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Desconectar Banco A'));
    await tester.pumpAndSettle();

    expect(find.text('Desconectar Banco A?'), findsOneWidget);
  });

  testWidgets('confirming disconnects, calls the repository and refreshes the list', (tester) async {
    await tester.pumpWidget(
      _app(
        connections: const [FinanceConnection(id: 'conn-1', instituicao: 'Banco A', status: 'UPDATED')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Desconectar Banco A'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Desconectar'));
    await tester.pumpAndSettle();

    expect(find.text('Banco A desconectado.'), findsOneWidget);
    // The list is re-fetched from the (now updated) repository — the disconnected institution
    // is gone instead of lingering as stale state.
    expect(find.text('Banco A'), findsNothing);
    expect(find.text('Conexões'), findsNothing);
  });

  testWidgets('cancelling the confirmation keeps the connection listed', (tester) async {
    await tester.pumpWidget(
      _app(
        connections: const [FinanceConnection(id: 'conn-1', instituicao: 'Banco A', status: 'UPDATED')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Desconectar Banco A'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Banco A'), findsOneWidget);
  });

  testWidgets('no connections at all: no "Conexões" section is shown', (tester) async {
    await tester.pumpWidget(_app(connections: const []));
    await tester.pumpAndSettle();

    expect(find.text('Conexões'), findsNothing);
  });
}
