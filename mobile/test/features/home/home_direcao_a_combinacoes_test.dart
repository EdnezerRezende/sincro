// Direção A em TODAS as combinações da Home (2 layouts × 3 estilos) e nos dois temas:
// a estrutura é a mesma — saudação, cartão de destaque de Finanças, cartões agrupados
// (`SectionCard`) e rodapé de emergência fixo, alcançável sem rolar — e nenhuma cor
// hard-coded quebra o tema escuro (renderiza sem exceção nos dois temas).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/core/widgets/section_card.dart';
import 'package:sincro_mobile/core/widgets/tonal_panel.dart';
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
import 'package:sincro_mobile/features/trusted_contacts/trusted_contact.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';

List<Override> _overrides(HomeLayoutMode modo, HomeDesignStyle design) => [
      homeLayoutModeProvider.overrideWith((ref) async => modo),
      homeDesignStyleProvider.overrideWith((ref) async => design),
      upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
      biofeedbackAtivoProvider.overrideWith((ref) async => false),
      gmailConnectionStatusProvider.overrideWith(
        (ref) async => const GmailConnectionStatus(connected: true, gmailEmail: 'ana@exemplo.com'),
      ),
      financeSummaryProvider.overrideWith((ref) async => FinanceSummary(
            saldoLivre: 1240,
            saldoContas: 0,
            faturasAbertas: 0,
            despesasPendentesCiclo: 0,
            cicloFim: DateTime.utc(2026, 10, 4),
          )),
      lancamentosPendentesProvider.overrideWith((ref) async => <LancamentoFinanceiro>[]),
      trustedContactsListProvider.overrideWith((ref) async => const [
            TrustedContact(id: 'c1', nome: 'Marina', relacao: 'FAMILIAR', whatsapp: '+5511999990000', prioridade: 0),
          ]),
    ];

Future<void> _pump(WidgetTester tester, HomeLayoutMode modo, HomeDesignStyle design, ThemeData theme) async {
  // Viewport de celular (prancha 390×844) para validar "emergência alcançável sem rolar".
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(modo, design),
    child: MaterialApp(theme: theme, home: const HomeScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final modo in HomeLayoutMode.values) {
    for (final design in HomeDesignStyle.values) {
      group('Home direção A (${modo.name}/${design.name})', () {
        testWidgets('tem saudação, destaque de Finanças, cartões agrupados e emergência fixa', (tester) async {
          await _pump(tester, modo, design, sincroLightTheme);

          expect(find.text('Você está em dia'), findsOneWidget);
          expect(find.text('Tudo sob controle'), findsOneWidget);
          expect(find.text('Saldo Livre'), findsOneWidget);
          expect(find.textContaining('1.240,00'), findsOneWidget);
          expect(find.text('Ver finanças'), findsOneWidget);
          expect(find.byType(TonalPanel), findsOneWidget);
          // Nas abas só a aba "Hoje" está montada; no resumo os dois grupos aparecem juntos.
          expect(find.byType(SectionCard), modo == HomeLayoutMode.resumo ? findsNWidgets(2) : findsOneWidget);
          expect(find.text('Caixa de Entrada'), findsOneWidget);
          expect(find.text('Próximos eventos'), findsOneWidget);
          expect(find.text('Biofeedback'), findsOneWidget);

          // Nada de "Finanças" repetido como título: o cartão se identifica pelo saldo.
          expect(find.text('Finanças'), findsNothing);

          // Emergência sempre alcançável, sem rolar, dentro da tela.
          final button = find.text('Avisar Rede de Apoio');
          expect(button, findsOneWidget);
          final rect = tester.getRect(button);
          expect(rect.bottom, lessThanOrEqualTo(844));
          expect(rect.top, greaterThan(0));
        });

        testWidgets('renderiza sem exceção no tema escuro', (tester) async {
          await _pump(tester, modo, design, sincroDarkTheme);
          expect(tester.takeException(), isNull);
          expect(find.text('Você está em dia'), findsOneWidget);
          expect(find.text('Avisar Rede de Apoio'), findsOneWidget);
        });
      });
    }
  }

  testWidgets('nas abas, "Apoio" mostra os dois atalhos e a emergência continua visível', (tester) async {
    await _pump(tester, HomeLayoutMode.abas, HomeDesignStyle.moderno, sincroLightTheme);
    await tester.tap(find.widgetWithText(Tab, 'Apoio'));
    await tester.pumpAndSettle();
    expect(find.text('Encontrar profissional'), findsOneWidget);
    expect(find.text('Alívio sensorial'), findsOneWidget);
    expect(find.text('Avisar Rede de Apoio'), findsOneWidget);
  });

  testWidgets('Funcional Direto nomeia os grupos e mostra o status do dia', (tester) async {
    await _pump(tester, HomeLayoutMode.resumo, HomeDesignStyle.funcional, sincroLightTheme);
    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Apoio'), findsOneWidget);
    expect(find.text('Status do dia'), findsOneWidget);
    expect(find.text('Monitoramento inativo'), findsOneWidget);
    // Traço do estilo: só o dado, sem prosa.
    expect(find.text('ana@exemplo.com'), findsOneWidget);
  });
}
