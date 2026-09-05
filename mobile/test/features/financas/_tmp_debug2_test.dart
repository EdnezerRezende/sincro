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
  testWidgets('debug overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = (details) {
      errors.add(details);
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financeSummaryRepositoryProvider.overrideWithValue(_NoopSyncSummaryRepository()),
          financeSummaryProvider.overrideWith((ref) async => FinanceSummary(
            saldoLivre: 1284.37,
            contas: [
              const FinanceAccountSummary(id: 'a', tipo: 'CORRENTE', nome: 'Banco do Brasil Conta Corrente', saldoOuFatura: 1284.37),
              FinanceAccountSummary(id: 'b', tipo: 'CARTAO_CREDITO', nome: 'Cartão Nubank Ultravioleta', saldoOuFatura: 987.65, vencimentoFatura: DateTime(2026,9,15)),
            ],
            boletos: [BoletoSummary(id: 'x', valor: 200, vencimento: DateTime(2026,9,1))],
          )),
          financeConnectionsProvider.overrideWith((ref) async => const [
            FinanceConnection(id: 'c1', instituicao: 'Banco Teste', status: 'UPDATED'),
          ]),
        ],
        child: MaterialApp(
          theme: sincroLightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: const FinancasScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    for (final e in errors) {
      // ignore: avoid_print
      print('=== FlutterError ===');
      print(e.summary);
      print(e.toString());
    }
  });
}
