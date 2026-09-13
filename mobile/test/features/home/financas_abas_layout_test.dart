// Finanças deve sempre ser o primeiro item, único acima das abas: um card fixo com Saldo Livre
// e "Ver finanças", nunca mais uma aba disputando espaço com as outras seções.
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

Widget _app({required HomeDesignStyle design}) {
  return ProviderScope(
    overrides: [
      homeLayoutModeProvider.overrideWith((ref) async => HomeLayoutMode.abas),
      homeDesignStyleProvider.overrideWith((ref) async => design),
      upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
      biofeedbackAtivoProvider.overrideWith((ref) async => false),
      gmailConnectionStatusProvider.overrideWith(
        (ref) async => const GmailConnectionStatus(connected: false),
      ),
      financeSummaryProvider.overrideWith(
        (ref) async => FinanceSummary(
          saldoLivre: 1234.56,
          saldoContas: 1234.56,
          faturasAbertas: 0,
          despesasPendentesCiclo: 0,
          cicloFim: DateTime.utc(2026, 9, 30),
        ),
      ),
      lancamentosPendentesProvider.overrideWith(
        (ref) async => const <LancamentoFinanceiro>[],
      ),
      trustedContactsListProvider.overrideWith((ref) async => []),
    ],
    child: MaterialApp(theme: sincroLightTheme, home: const HomeScreen()),
  );
}

void main() {
  for (final design in HomeDesignStyle.values) {
    group('Abas layout Finanças placement (${design.name})', () {
      testWidgets('Finanças is a fixed card above the tabs, not a tab of its own', (
        tester,
      ) async {
        await tester.pumpWidget(_app(design: design));
        await tester.pumpAndSettle();

        // Não é mais uma aba: só "Hoje" e "Apoio".
        expect(find.widgetWithText(Tab, 'Hoje'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Apoio'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Finanças'), findsNothing);

        // O card fixo mostra o saldo livre sem precisar trocar de aba.
        expect(find.textContaining('1.234,56'), findsOneWidget);
        expect(find.textContaining('Ver finanças'), findsOneWidget);

        // Continua acessível a partir de qualquer aba.
        await tester.tap(find.widgetWithText(Tab, 'Apoio'));
        await tester.pumpAndSettle();
        expect(find.textContaining('1.234,56'), findsOneWidget);
      });
    });
  }
}
