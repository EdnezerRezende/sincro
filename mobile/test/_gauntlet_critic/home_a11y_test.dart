import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/home/home_screen.dart';
import 'package:sincro_mobile/features/home/home_providers.dart';
import 'package:sincro_mobile/features/home/home_layout_mode.dart';
import 'package:sincro_mobile/features/home/home_design_style.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';
import 'package:sincro_mobile/features/financas/finance_providers.dart';
import 'package:sincro_mobile/features/financas/finance_connection.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/trusted_contacts/trusted_contacts_providers.dart';

// Never completes -> forces the loading branch of a FutureProvider.
Future<T> _pending<T>() => Completer<T>().future;

Widget _app({
  required List<Override> overrides,
  required Brightness brightness,
  required List<String> navLog,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: brightness == Brightness.light ? sincroLightTheme : sincroDarkTheme,
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
  required AsyncValue<List<CalendarEvent>> cal,
  required AsyncValue<bool> bio,
}) {
  return [
    homeLayoutModeProvider.overrideWith((ref) async => HomeLayoutMode.resumo),
    homeDesignStyleProvider.overrideWith((ref) async => HomeDesignStyle.funcional),
    upcomingEventsProvider.overrideWith((ref) => cal.when(
          data: (d) async => d,
          loading: () => _pending<List<CalendarEvent>>(),
          error: (e, st) => Future<List<CalendarEvent>>.error(e, st),
        )),
    biofeedbackAtivoProvider.overrideWith((ref) => bio.when(
          data: (d) async => d,
          loading: () => _pending<bool>(),
          error: (e, st) => Future<bool>.error(e, st),
        )),
    gmailConnectionStatusProvider.overrideWith(
        (ref) async => GmailConnectionStatus(connected: false)),
    financeConnectionsProvider.overrideWith(
        (ref) async => <FinanceConnection>[]),
    trustedContactsListProvider.overrideWith((ref) async => []),
  ];
}

/// Walks the semantics tree and returns nodes whose label matches.
SemanticsNode? _findNode(SemanticsNode root, bool Function(SemanticsNode) pred) {
  SemanticsNode? found;
  void visit(SemanticsNode n) {
    if (found != null) return;
    if (pred(n)) {
      found = n;
      return;
    }
    n.visitChildren((c) {
      visit(c);
      return found == null;
    });
  }
  visit(root);
  return found;
}

void main() {
  group('Funcional a11y — executed semantics', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final bname = brightness == Brightness.light ? 'light' : 'dark';

      testWidgets('[$bname] calendar DATA + resource cards: tap action + 48dp',
          (tester) async {
        final handle = tester.ensureSemantics();
        final navLog = <String>[];
        await tester.pumpWidget(_app(
          overrides: _base(
            cal: AsyncValue.data([]),
            bio: const AsyncValue.data(true),
          ),
          brightness: brightness,
          navLog: navLog,
        ));
        await tester.pumpAndSettle();

        final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
        for (final label in [
          'Calendário — nenhum evento',
          'Profissionais',
          'Alívio sensorial',
        ]) {
          final node = _findNode(root, (n) => n.label == label);
          expect(node, isNotNull, reason: 'no semantics node labelled "$label"');
          expect(node!.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
              reason: '"$label" has no tap action');
          expect(node.getSemanticsData().hasFlag(SemanticsFlag.isButton), isTrue,
              reason: '"$label" is not flagged as a button');
          final h = node.rect.height;
          expect(h, greaterThanOrEqualTo(48.0),
              reason: '"$label" tap target height is $h dp (<48)');
          print('OK [$bname] "$label" h=${h.toStringAsFixed(1)}dp tap=true button=true');
        }
        handle.dispose();
      });

      testWidgets('[$bname] calendar LOADING state is tappable and navigates',
          (tester) async {
        final handle = tester.ensureSemantics();
        final navLog = <String>[];
        await tester.pumpWidget(_app(
          overrides: _base(
            cal: const AsyncValue.loading(),
            bio: const AsyncValue.loading(),
          ),
          brightness: brightness,
          navLog: navLog,
        ));
        await tester.pump(const Duration(milliseconds: 100));

        final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
        final node = _findNode(root, (n) => n.label == 'Calendário — carregando');
        expect(node, isNotNull, reason: 'loading state has no semantics node');
        expect(node!.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
            reason: 'loading state has no tap action');
        final h = node.rect.height;
        expect(h, greaterThanOrEqualTo(48.0),
            reason: 'loading tap target is $h dp (<48)');
        print('OK [$bname] LOADING h=${h.toStringAsFixed(1)}dp tap=true');

        // Real gesture, not just the semantic flag.
        await tester.tap(find.bySemanticsLabel('Calendário — carregando'));
        await tester.pumpAndSettle();
        expect(navLog, contains('/calendar'),
            reason: 'tapping the loading card did not navigate; navLog=$navLog');
        print('OK [$bname] LOADING real tap navigated -> $navLog');
        handle.dispose();
      });

      testWidgets('[$bname] calendar ERROR state is tappable and navigates',
          (tester) async {
        final handle = tester.ensureSemantics();
        final navLog = <String>[];
        await tester.pumpWidget(_app(
          overrides: _base(
            cal: AsyncValue.error(Exception('boom'), StackTrace.empty),
            bio: AsyncValue.error(Exception('boom'), StackTrace.empty),
          ),
          brightness: brightness,
          navLog: navLog,
        ));
        await tester.pumpAndSettle();

        final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
        final node = _findNode(root, (n) => n.label == 'Calendário — ver mais');
        expect(node, isNotNull, reason: 'error state has no semantics node');
        expect(node!.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(node.rect.height, greaterThanOrEqualTo(48.0));
        print('OK [$bname] ERROR h=${node.rect.height.toStringAsFixed(1)}dp tap=true');

        await tester.tap(find.bySemanticsLabel('Calendário — ver mais'));
        await tester.pumpAndSettle();
        expect(navLog, contains('/calendar'));
        handle.dispose();
      });
    }

    testWidgets('StatusSummary renders 3 DISTINCT states', (tester) async {
      final texts = <String, String>{};
      for (final entry in {
        'data-true': const AsyncValue<bool>.data(true),
        'data-false': const AsyncValue<bool>.data(false),
        'loading': const AsyncValue<bool>.loading(),
        'error': AsyncValue<bool>.error(Exception('x'), StackTrace.empty),
      }.entries) {
        final navLog = <String>[];
        await tester.pumpWidget(_app(
          overrides: _base(cal: AsyncValue.data([]), bio: entry.value),
          brightness: Brightness.light,
          navLog: navLog,
        ));
        await tester.pump(const Duration(milliseconds: 100));
        for (final s in [
          'Monitoramento ativo',
          'Monitoramento inativo',
          'Verificando...',
          'Dados indisponíveis',
        ]) {
          if (find.text(s).evaluate().isNotEmpty) texts[entry.key] = s;
        }
      }
      print('StatusSummary states: $texts');
      expect(texts.length, 4);
      expect(texts.values.toSet().length, 4,
          reason: 'states are not distinct: $texts');
    });
  });
}
