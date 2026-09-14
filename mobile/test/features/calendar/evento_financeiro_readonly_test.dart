import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';

void main() {
  testWidgets('evento gerado por Finanças abre em modo somente leitura, sem editar/excluir', (tester) async {
    final hoje = DateTime.now();
    final evento = CalendarEvent(
      id: 'ev1',
      titulo: 'Pagar: Nubank',
      descricao: 'Valor: R\$ 500.00',
      dataHoraInicio: DateTime(hoje.year, hoje.month, hoje.day),
      dataHoraFim: DateTime(hoje.year, hoje.month, hoje.day),
      ehDiaInteiro: true,
      categoria: CategoriaEvento.financeiro,
      lancamentoId: 'lanc-1',
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

    await tester.tap(find.text('Ver detalhes'));
    await tester.pumpAndSettle();

    expect(find.text('Pagar: Nubank'), findsWidgets);
    expect(
      find.textContaining('Gerado a partir de uma despesa em Finanças'),
      findsOneWidget,
    );
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Excluir'), findsNothing);
    expect(find.text('Salvar'), findsNothing);
  });
}
