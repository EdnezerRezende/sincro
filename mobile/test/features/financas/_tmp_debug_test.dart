import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/financas/finance_connection.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';
import 'package:sincro_mobile/features/financas/finance_summary_repository.dart';
import 'package:sincro_mobile/features/financas/financas_screen.dart';

class _NoopSyncSummaryRepository extends FinanceSummaryRepository {
  _NoopSyncSummaryRepository() : super(Dio());
  @override
  Future<void> sync() async {}
  @override
  Future<FinanceSummary> getResumo() async => throw UnimplementedError();
}

void main() {
  testWidgets('debug', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeSummaryRepositoryProvider.overrideWithValue(_NoopSyncSummaryRepository()),
          financeSummaryProvider.overrideWith((ref) async => const FinanceSummary(saldoLivre: 100, contas: [
            FinanceAccountSummary(id: 'a', tipo: 'CORRENTE', nome: 'Teste', saldoOuFatura: 100),
          ], boletos: [])),
          financeConnectionsProvider.overrideWith((ref) async => throw Exception('boom')),
        ],
        child: MaterialApp(
          theme: sincroLightTheme,
          home: const FinancasScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDumpApp();
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    // ignore: avoid_print
    print('TEXTS: $texts');
  });
}
