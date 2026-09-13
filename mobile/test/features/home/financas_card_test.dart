// Covers two whole-branch review findings on the Home Finanças card (all 3 design styles):
// - the error state must still be a tappable entry point into FinancasScreen (there is no
//   other way to reach it from the app), instead of disappearing (SizedBox.shrink).
// - the data state must show a calm, non-alarmist pending count ("N lançamentos para revisar,
//   sem pressa") plus a "Ver finanças" CTA below the Saldo Livre value, per the design spec.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/home/home_design_style.dart';
import 'package:sincro_mobile/features/home/home_layout_mode.dart';
import 'package:sincro_mobile/features/home/home_providers.dart';
import 'package:sincro_mobile/features/home/home_screen.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';

LancamentoFinanceiro _pendente(String id) {
  return LancamentoFinanceiro(
    id: id,
    tipo: TipoLancamento.despesa,
    descricao: 'Pendente $id',
    instituicao: 'Nubank',
    valor: 100,
    dataVencimento: DateTime.utc(2026, 9, 20),
    dataCompetencia: DateTime.utc(2026, 9, 20),
    status: StatusLancamento.pendenteRevisao,
    origem: OrigemLancamento.emailParser,
    isPago: false,
    codigoBarras: null,
    cartaoId: null,
    contaId: null,
  );
}

List<Override> _base({
  required HomeDesignStyle design,
  required AsyncValue<FinanceSummary> summary,
  required AsyncValue<List<LancamentoFinanceiro>> pendentes,
}) {
  return [
    homeLayoutModeProvider.overrideWith((ref) async => HomeLayoutMode.resumo),
    homeDesignStyleProvider.overrideWith((ref) async => design),
    upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
    biofeedbackAtivoProvider.overrideWith((ref) async => false),
    gmailConnectionStatusProvider.overrideWith(
      (ref) async => const GmailConnectionStatus(connected: false),
    ),
    financeSummaryProvider.overrideWith(
      (ref) => summary.when(
        data: (d) async => d,
        loading: () => Future<FinanceSummary>.delayed(const Duration(days: 1)),
        error: (e, st) => Future<FinanceSummary>.error(e, st),
      ),
    ),
    lancamentosPendentesProvider.overrideWith(
      (ref) => pendentes.when(
        data: (d) async => d,
        loading: () =>
            Future<List<LancamentoFinanceiro>>.delayed(const Duration(days: 1)),
        error: (e, st) => Future<List<LancamentoFinanceiro>>.error(e, st),
      ),
    ),
    trustedContactsListProvider.overrideWith((ref) async => []),
  ];
}

Widget _app({required List<Override> overrides, required List<String> navLog}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: sincroLightTheme,
      home: const HomeScreen(),
      onGenerateRoute: (s) {
        navLog.add(s.name ?? '?');
        return MaterialPageRoute(
          builder: (_) => Scaffold(body: Text('ROUTE ${s.name}')),
          settings: s,
        );
      },
    ),
  );
}

void main() {
  for (final design in HomeDesignStyle.values) {
    group('Finanças card (${design.name})', () {
      testWidgets(
        'error state is still tappable and opens FinancasScreen',
        (tester) async {
          await tester.pumpWidget(
            _app(
              overrides: _base(
                design: design,
                summary: AsyncValue.error('boom', StackTrace.empty),
                pendentes: const AsyncValue.data([]),
              ),
              navLog: [],
            ),
          );
          await tester.pumpAndSettle();

          final placeholder = find.textContaining('Não foi possível carregar');
          expect(placeholder, findsOneWidget);

          await tester.tap(placeholder);
          await tester.pumpAndSettle();

          expect(find.text('Finanças'), findsWidgets);
        },
      );

      testWidgets(
        'shows the pending count and a "Ver finanças" CTA when there are pendências',
        (tester) async {
          await tester.pumpWidget(
            _app(
              overrides: _base(
                design: design,
                summary: AsyncValue.data(
                  FinanceSummary(
                    saldoLivre: 1000,
                    saldoContas: 1000,
                    faturasAbertas: 0,
                    despesasPendentesCiclo: 0,
                    cicloFim: DateTime.utc(2026, 9, 30),
                  ),
                ),
                pendentes: AsyncValue.data([_pendente('l1'), _pendente('l2')]),
              ),
              navLog: [],
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.textContaining('2 lançamentos para revisar, sem pressa'),
            findsOneWidget,
          );
          expect(find.textContaining('Ver finanças'), findsOneWidget);
        },
      );

      testWidgets(
        'omits the pending count line when there are no pendências',
        (tester) async {
          await tester.pumpWidget(
            _app(
              overrides: _base(
                design: design,
                summary: AsyncValue.data(
                  FinanceSummary(
                    saldoLivre: 1000,
                    saldoContas: 1000,
                    faturasAbertas: 0,
                    despesasPendentesCiclo: 0,
                    cicloFim: DateTime.utc(2026, 9, 30),
                  ),
                ),
                pendentes: const AsyncValue.data([]),
              ),
              navLog: [],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.textContaining('para revisar'), findsNothing);
          expect(find.textContaining('Ver finanças'), findsOneWidget);
        },
      );
    });
  }
}
