import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/core/widgets/section_card.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_summary.dart';
import 'package:sincro_mobile/features/financas/financas_screen.dart';
import 'package:sincro_mobile/features/financas/lancamento_financeiro.dart';
import 'package:sincro_mobile/features/home/home_design_style.dart';
import 'package:sincro_mobile/features/home/home_layout_mode.dart';
import 'package:sincro_mobile/features/home/home_providers.dart';
import 'package:sincro_mobile/features/home/home_screen.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';

List<Override> _overrides() => [
      homeLayoutModeProvider.overrideWith((ref) async => HomeLayoutMode.resumo),
      homeDesignStyleProvider.overrideWith((ref) async => HomeDesignStyle.minimalista),
      upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
      biofeedbackAtivoProvider.overrideWith((ref) async => false),
      gmailConnectionStatusProvider.overrideWith((ref) async => const GmailConnectionStatus(connected: false)),
      financeSummaryProvider.overrideWith((ref) async => FinanceSummary(
            saldoLivre: 1240,
            saldoContas: 0,
            faturasAbertas: 0,
            despesasPendentesCiclo: 0,
            cicloFim: DateTime.utc(2026, 10, 4),
          )),
      lancamentosPendentesProvider.overrideWith((ref) async => <LancamentoFinanceiro>[]),
      trustedContactsListProvider.overrideWith((ref) async => []),
    ];

Future<void> pumpHomeMinimalistaResumo(WidgetTester tester) => tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(theme: sincroLightTheme, home: const HomeScreen()),
    ));

void main() {
  testWidgets('minimalista/resumo shows greeting, finance hero, grouped rows, Apoio and pinned emergency', (tester) async {
    await pumpHomeMinimalistaResumo(tester);
    await tester.pumpAndSettle();

    expect(find.text('Você está em dia'), findsOneWidget);
    expect(find.text('Tudo sob controle'), findsOneWidget);
    expect(find.text('Saldo Livre'), findsOneWidget);
    expect(find.text('Ver finanças'), findsOneWidget);
    expect(find.text('Caixa de Entrada'), findsOneWidget);
    expect(find.text('Próximos eventos'), findsOneWidget);
    expect(find.text('Biofeedback'), findsOneWidget);
    expect(find.text('Apoio'), findsOneWidget);
    expect(find.text('Encontrar profissional'), findsOneWidget);
    expect(find.text('Alívio sensorial'), findsOneWidget);
    expect(find.byType(SectionCard), findsNWidgets(2));

    // botão de emergência fora da rolagem: continua encontrável após rolar a lista até o fim
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Avisar Rede de Apoio'), findsOneWidget);
    final buttonRect = tester.getRect(find.text('Avisar Rede de Apoio'));
    expect(buttonRect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio));
  });

  testWidgets('finance hero card has a "Finanças" semantics label and is fully tappable into FinancasScreen', (tester) async {
    final handle = tester.ensureSemantics();

    await pumpHomeMinimalistaResumo(tester);
    await tester.pumpAndSettle();

    // O cartão hero não mostra um título "Finanças" visível — a leitura por voz precisa dizer
    // "Finanças" explicitamente (mesmo padrão de `_FinancasCard` com `showTitle: false`).
    expect(find.bySemanticsLabel(RegExp('Finanças')), findsOneWidget);

    // O cartão inteiro é tocável, não só o botão "Ver finanças".
    await tester.tap(find.text('Saldo Livre'));
    await tester.pumpAndSettle();
    expect(find.byType(FinancasScreen), findsOneWidget);

    handle.dispose();
  });
}
