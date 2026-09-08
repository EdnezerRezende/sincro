// Covers the parity gap between the Funcional Direto Home style and the other two styles
// (Minimalista Refinado, Moderno Suave) for the E-mail and Biofeedback cards: in the
// connected/active state, both cards must be tappable and navigate to their detail screen,
// and the Biofeedback card must show the real bpm/estado instead of a fixed "Ativo" label.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/home/home_screen.dart';
import 'package:sincro_mobile/features/home/home_layout_mode.dart';
import 'package:sincro_mobile/features/home/home_design_style.dart';
import 'package:sincro_mobile/features/home/home_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_connection.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';

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

List<Override> _base({
  required AsyncValue<GmailConnectionStatus> gmail,
  required AsyncValue<bool> bio,
  required AsyncValue<BiofeedbackSummary?> resumo,
}) {
  return [
    homeLayoutModeProvider.overrideWith((ref) async => HomeLayoutMode.resumo),
    homeDesignStyleProvider.overrideWith(
      (ref) async => HomeDesignStyle.funcional,
    ),
    upcomingEventsProvider.overrideWith(
      (ref) async => <CalendarEvent>[],
    ),
    biofeedbackAtivoProvider.overrideWith(
      (ref) => bio.when(
        data: (d) async => d,
        loading: () => Future<bool>.delayed(const Duration(days: 1)),
        error: (e, st) => Future<bool>.error(e, st),
      ),
    ),
    biofeedbackResumoProvider.overrideWith(
      (ref) => resumo.when(
        data: (d) async => d,
        loading: () => Future<BiofeedbackSummary?>.delayed(
          const Duration(days: 1),
        ),
        error: (e, st) => Future<BiofeedbackSummary?>.error(e, st),
      ),
    ),
    gmailConnectionStatusProvider.overrideWith(
      (ref) => gmail.when(
        data: (d) async => d,
        loading: () => Future<GmailConnectionStatus>.delayed(
          const Duration(days: 1),
        ),
        error: (e, st) => Future<GmailConnectionStatus>.error(e, st),
      ),
    ),
    financeConnectionsProvider.overrideWith(
      (ref) async => <FinanceConnection>[],
    ),
    trustedContactsListProvider.overrideWith((ref) async => []),
  ];
}

void main() {
  group('Funcional Direto — Gmail card parity', () {
    testWidgets('connected state shows the email and navigates to /inbox on tap', (
      tester,
    ) async {
      final navLog = <String>[];
      await tester.pumpWidget(
        _app(
          overrides: _base(
            gmail: const AsyncValue.data(
              GmailConnectionStatus(
                connected: true,
                gmailEmail: 'ana@exemplo.com',
              ),
            ),
            bio: const AsyncValue.data(false),
            resumo: const AsyncValue.data(null),
          ),
          navLog: navLog,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ana@exemplo.com'), findsOneWidget);

      await tester.tap(find.text('ana@exemplo.com'));
      await tester.pumpAndSettle();

      expect(navLog, contains('/inbox'));
    });
  });

  group('Funcional Direto — Biofeedback card parity', () {
    testWidgets(
      'active state shows the real bpm + estado (not a fixed label) and navigates to /biofeedback on tap',
      (tester) async {
        final navLog = <String>[];
        await tester.pumpWidget(
          _app(
            overrides: _base(
              gmail: const AsyncValue.data(GmailConnectionStatus(connected: false)),
              bio: const AsyncValue.data(true),
              resumo: AsyncValue.data(
                BiofeedbackSummary(
                  ultimaFc: 72.4,
                  mediaFcHoje: 70,
                  mediaVfcHoje: 45,
                  estadoEstresse: EstadoEstresse.calmo,
                  atualizadoEm: DateTime(2026, 1, 1),
                ),
              ),
            ),
            navLog: navLog,
          ),
        );
        await tester.pumpAndSettle();

        // Real data, not the old fixed "Ativo" label.
        expect(find.text('Ativo', findRichText: false), findsNothing);
        expect(find.text('72 bpm · Calmo'), findsOneWidget);

        await tester.tap(find.text('72 bpm · Calmo'));
        await tester.pumpAndSettle();

        expect(navLog, contains('/biofeedback'));
      },
    );

    testWidgets(
      'active state with no reading yet shows a state instead of throwing',
      (tester) async {
        final navLog = <String>[];
        await tester.pumpWidget(
          _app(
            overrides: _base(
              gmail: const AsyncValue.data(GmailConnectionStatus(connected: false)),
              bio: const AsyncValue.data(true),
              resumo: const AsyncValue.data(null),
            ),
            navLog: navLog,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Nenhum dado disponível ainda'), findsOneWidget);
      },
    );
  });
}
