// THROWAWAY verification test for Gauntlet round 3 fixes on financas_screen.dart.
// Not part of the permanent suite -- deleted after manual verification.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  Future<FinanceSummary> getResumo() async => throw UnimplementedError('bypassed by provider override');
}

FinanceSummary _summaryWith({
  required List<FinanceAccountSummary> contas,
  double saldoLivre = 1284.37,
  List<BoletoSummary> boletos = const [],
}) {
  return FinanceSummary(saldoLivre: saldoLivre, contas: contas, boletos: boletos);
}

final _correnteAccount = FinanceAccountSummary(
  id: 'acc-1',
  tipo: 'CORRENTE',
  nome: 'Banco do Brasil Conta Corrente',
  saldoOuFatura: 1284.37,
);

final _cartaoAccount = FinanceAccountSummary(
  id: 'acc-2',
  tipo: 'CARTAO_CREDITO',
  nome: 'Cartão Nubank Ultravioleta',
  saldoOuFatura: 987.65,
  vencimentoFatura: DateTime(2026, 9, 15),
);

final _boleto = BoletoSummary(id: 'bol-1', valor: 200.0, vencimento: DateTime(2026, 9, 1));

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FinanceSummary summary,
  required Future<List<FinanceConnection>> Function(Ref ref) connections,
  required ThemeData theme,
  required double textScale,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeSummaryRepositoryProvider.overrideWithValue(_NoopSyncSummaryRepository()),
        financeSummaryProvider.overrideWith((ref) async => summary),
        financeConnectionsProvider.overrideWith(connections),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const FinancasScreen(),
      ),
    ),
  );

  // initState's addPostFrameCallback fires the (no-op) sync + provider invalidation.
  await tester.pumpAndSettle();
}

void main() {
  final healthyConnections = [
    const FinanceConnection(id: 'c1', instituicao: 'Banco Teste', status: 'UPDATED'),
  ];

  for (final textScale in [1.0, 1.5, 2.0]) {
    for (final themeEntry in {'light': sincroLightTheme, 'dark': sincroDarkTheme}.entries) {
      testWidgets(
        'renders without paint exceptions at textScale $textScale (${themeEntry.key})',
        (tester) async {
          await _pumpScreen(
            tester,
            summary: _summaryWith(contas: [_correnteAccount, _cartaoAccount], boletos: [_boleto]),
            connections: (ref) async => healthyConnections,
            theme: themeEntry.value,
            textScale: textScale,
          );

          expect(tester.takeException(), isNull, reason: 'no paint/layout exception expected');

          // --- Gap 5: CORRENTE gets a real label + bank icon, not the generic person icon ---
          expect(find.textContaining('Conta corrente'), findsWidgets);
          expect(find.byIcon(Icons.account_balance), findsWidgets);
          expect(find.byIcon(Icons.account_circle), findsNothing,
              reason: 'CORRENTE must never fall through to the generic person icon');

          // --- Gap 2: hero number stays on one line, never wraps mid-digit ---
          final heroParagraphs = tester.renderObjectList<RenderParagraph>(
            find.descendant(of: find.byType(FittedBox), matching: find.textContaining('R\$')),
          );
          for (final p in heroParagraphs) {
            expect(p.didExceedMaxLines, isFalse,
                reason: 'hero/value text must never wrap onto a second line');
          }

          // --- Gap 1/6: account name and "a vencer" item name are not reduced to ~2 chars ---
          final nameBox = tester.renderObject<RenderBox>(find.text(_correnteAccount.nome));
          expect(nameBox.size.width, greaterThan(60),
              reason: 'account name column collapsed to a sliver at textScale $textScale');

          final boletoLabel = 'Boleto · vence 01/09';
          expect(find.text(boletoLabel), findsOneWidget);
          final boletoBox = tester.renderObject<RenderBox>(find.text(boletoLabel));
          expect(boletoBox.size.width, greaterThan(60),
              reason: 'boleto date label collapsed at textScale $textScale');

          // --- Gap 10: "fatura" marker survives as its own element (never truncated away) ---
          expect(find.text('fatura'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('empty accounts state never asserts a false R\$ 0,00 balance', (tester) async {
    await _pumpScreen(
      tester,
      summary: _summaryWith(contas: [], saldoLivre: 0),
      connections: (ref) async => <FinanceConnection>[],
      theme: sincroLightTheme,
      textScale: 1.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Saldo livre'), findsNothing);
    expect(find.textContaining('R\$ 0,00'), findsNothing);
    expect(find.textContaining('Conecte uma conta para ver seu saldo'), findsOneWidget);
  });

  testWidgets('broken connections provider shows a caution banner instead of vanishing', (tester) async {
    await _pumpScreen(
      tester,
      summary: _summaryWith(contas: [_correnteAccount]),
      connections: (ref) async => throw Exception('conexoes down'),
      theme: sincroLightTheme,
      textScale: 1.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('conexõe'), findsWidgets, reason: 'health-check failure must not disappear silently');
    expect(find.textContaining('Não foi possível verificar suas conexões agora'), findsOneWidget);
  });

  testWidgets('UPDATING connection is shown as syncing, never as "precisa de atenção"', (tester) async {
    await _pumpScreen(
      tester,
      summary: _summaryWith(contas: [_correnteAccount]),
      connections: (ref) async => [const FinanceConnection(id: 'c1', instituicao: 'Banco X', status: 'UPDATING')],
      theme: sincroLightTheme,
      textScale: 1.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('precisa'), findsNothing,
        reason: 'UPDATING is a healthy transitory state, must never trigger the attention card');
    expect(find.textContaining('sincronizando'), findsWidgets);
  });

  testWidgets('a truly unknown status gets a calm generic treatment, not "status desconhecido"',
      (tester) async {
    await _pumpScreen(
      tester,
      summary: _summaryWith(contas: [_correnteAccount]),
      connections: (ref) async => [const FinanceConnection(id: 'c1', instituicao: 'Banco Y', status: 'SOME_NEW_STATUS')],
      theme: sincroLightTheme,
      textScale: 1.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('desconhecido'), findsNothing);
    expect(find.textContaining('precisa'), findsNothing);
  });

  testWidgets('credit-card fatura is consistently amber/debt in both sections, never a green check',
      (tester) async {
    await _pumpScreen(
      tester,
      summary: _summaryWith(contas: [_cartaoAccount]),
      connections: (ref) async => healthyConnections,
      theme: sincroLightTheme,
      textScale: 1.0,
    );

    expect(tester.takeException(), isNull);
    // Account-list row for the card shows a leading "-" (debt).
    expect(find.textContaining('- R\$'), findsOneWidget);
    // "A vencer" row for the very same fatura must NOT render the green "tudo bem" check icon.
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.schedule), findsWidgets);
  });
}
