import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';

void main() {
  testWidgets('evento manual abre no formulário de edição com seletor de categoria, sem opção Financeiro', (tester) async {
    final hoje = DateTime.now();
    final evento = CalendarEvent(
      id: 'ev2',
      titulo: 'Jantar com amigos',
      descricao: '',
      dataHoraInicio: DateTime(hoje.year, hoje.month, hoje.day, 20),
      dataHoraFim: DateTime(hoje.year, hoje.month, hoje.day, 22),
      categoria: CategoriaEvento.social,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gmailConnectionStatusProvider.overrideWith(
            (ref) async => const GmailConnectionStatus(connected: true),
          ),
          upcomingEventsProvider.overrideWith((ref) async => <CalendarEvent>[]),
          monthEventsProvider.overrideWith((ref, params) async => [evento]),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('${hoje.day}').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    expect(find.text('Categoria'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Social'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Trabalho'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Geral'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Financeiro'), findsNothing);
  });
}
