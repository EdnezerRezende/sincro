import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';

void main() {
  testWidgets('mostra o ícone e o tooltip correspondentes à categoria do evento', (tester) async {
    final hoje = DateTime.now();
    final evento = CalendarEvent(
      id: 'ev1',
      titulo: 'Reunião de trabalho',
      descricao: '',
      dataHoraInicio: DateTime(hoje.year, hoje.month, hoje.day, 10),
      dataHoraFim: DateTime(hoje.year, hoje.month, hoje.day, 11),
      categoria: CategoriaEvento.trabalho,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // `CalendarScreen` também lê `gmailConnectionStatusProvider` (mostra painel de
          // reconexão quando não conectado) e `upcomingEventsProvider` (seção "Próximos
          // eventos") — sem sobrescrever os dois, a tela tentaria uma chamada de rede real
          // via `apiClientProvider`, tornando o teste não-determinístico. Mesmo padrão de
          // override usado em `revalidation_test.dart`/`touch_target_test.dart`.
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

    // Abre a modal do dia de hoje tocando na célula correspondente (o número do dia
    // aparece só uma vez no grid de dias, já que `_DayCell` só renderiza dias do mês
    // atualmente exibido).
    await tester.tap(find.text('${hoje.day}').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Trabalho'), findsOneWidget);
  });
}
