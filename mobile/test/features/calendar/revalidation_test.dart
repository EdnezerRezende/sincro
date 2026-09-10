// Cobre as três correções desta rodada para o sintoma "evento criado num lado não aparece no
// outro": (1) puxar-para-atualizar realmente refaz as buscas de rede; (2) retomar o app
// (`AppLifecycleState.resumed`) revalida automaticamente, respeitando o intervalo mínimo entre
// revalidações; (3) um erro de escopo na seção "Próximos eventos" mostra o mesmo painel de
// "Reconectar Gmail" que já existia na visão do mês, em vez da mensagem genérica anterior.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_repository.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';
import 'package:sincro_mobile/features/email_triage/email_triage_providers.dart';
import 'package:sincro_mobile/features/email_triage/gmail_connection_repository.dart';

/// Repositório falso que conta quantas vezes cada método de listagem foi chamado, para provar
/// que invalidar os providers realmente dispara uma nova busca de rede (e não só reexibe o
/// último resultado em cache). O `Dio()` passado ao `super` nunca é usado de verdade: os dois
/// métodos relevantes são sobrescritos antes de qualquer chamada chegar a ele.
class _FakeCalendarRepository extends CalendarRepository {
  _FakeCalendarRepository() : super(Dio());

  int upcomingCalls = 0;
  int monthCalls = 0;
  Object? upcomingError;
  List<CalendarEvent> upcomingResult = const [];
  List<CalendarEvent> monthResult = const [];

  @override
  Future<List<CalendarEvent>> listUpcomingEvents() async {
    upcomingCalls++;
    final error = upcomingError;
    if (error != null) throw error;
    return upcomingResult;
  }

  @override
  Future<List<CalendarEvent>> listMonthEvents(int ano, int mes) async {
    monthCalls++;
    return monthResult;
  }
}

void main() {
  group('Pull-to-refresh', () {
    testWidgets(
      'Arrastar o RefreshIndicator invalida os providers e refaz as duas buscas',
      (WidgetTester tester) async {
        final fakeRepo = _FakeCalendarRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              calendarRepositoryProvider.overrideWithValue(fakeRepo),
              gmailConnectionStatusProvider.overrideWith(
                (ref) async => const GmailConnectionStatus(connected: true),
              ),
            ],
            child: const MaterialApp(home: CalendarScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Uma busca de cada ao montar a tela pela primeira vez.
        expect(fakeRepo.upcomingCalls, 1);
        expect(fakeRepo.monthCalls, 1);

        // Aciona o `RefreshIndicator` diretamente pelo seu estado — equivalente a um puxar para
        // baixo real, mas determinístico em teste (sem depender de geometria de gesto).
        final refreshState = tester.state<RefreshIndicatorState>(
          find.byType(RefreshIndicator),
        );
        unawaited(refreshState.show());
        await tester.pumpAndSettle();

        expect(
          fakeRepo.upcomingCalls,
          2,
          reason: 'Puxar para atualizar deveria refazer a busca de próximos eventos',
        );
        expect(
          fakeRepo.monthCalls,
          2,
          reason: 'Puxar para atualizar deveria refazer a busca do mês',
        );
      },
    );
  });

  group('Revalidação ao retomar o app', () {
    testWidgets(
      'AppLifecycleState.resumed dentro do intervalo mínimo NÃO revalida',
      (WidgetTester tester) async {
        final fakeRepo = _FakeCalendarRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              calendarRepositoryProvider.overrideWithValue(fakeRepo),
              gmailConnectionStatusProvider.overrideWith(
                (ref) async => const GmailConnectionStatus(connected: true),
              ),
            ],
            child: const MaterialApp(home: CalendarScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeRepo.upcomingCalls, 1);
        expect(fakeRepo.monthCalls, 1);

        // Retomar o app imediatamente (dentro do intervalo mínimo de 30s) NÃO deve revalidar —
        // é o caso de alternar de app rapidamente (notificação, teclado) que o intervalo mínimo
        // existe para evitar.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();

        expect(
          fakeRepo.upcomingCalls,
          1,
          reason: 'Retomar o app dentro do intervalo mínimo não deveria revalidar',
        );
        expect(fakeRepo.monthCalls, 1);
      },
    );

    // Único teste "lento" do arquivo: usa `tester.runAsync` para deixar ~31s de tempo REAL
    // decorrerem, porque `didChangeAppLifecycleState` compara `DateTime.now()` (relógio real, não
    // o relógio simulado do `WidgetTester`) contra `_kRevalidationMinInterval` — não há um seam de
    // injeção de relógio no widget para acelerar isso sem alterar o comportamento de produção.
    // Prova o caminho positivo que o teste anterior (dentro do intervalo) não cobre: passado o
    // intervalo mínimo, retomar o app REALMENTE revalida.
    testWidgets(
      'AppLifecycleState.resumed após o intervalo mínimo já ter decorrido revalida',
      (WidgetTester tester) async {
        final fakeRepo = _FakeCalendarRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              calendarRepositoryProvider.overrideWithValue(fakeRepo),
              gmailConnectionStatusProvider.overrideWith(
                (ref) async => const GmailConnectionStatus(connected: true),
              ),
            ],
            child: const MaterialApp(home: CalendarScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeRepo.upcomingCalls, 1);
        expect(fakeRepo.monthCalls, 1);

        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 31)),
        );

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();

        expect(
          fakeRepo.upcomingCalls,
          2,
          reason:
              'Retomar o app depois do intervalo mínimo deveria revalidar os próximos eventos',
        );
        expect(
          fakeRepo.monthCalls,
          2,
          reason: 'Retomar o app depois do intervalo mínimo deveria revalidar o mês',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets(
      'AppLifecycleState.resumed é ignorado para outros estados (paused, inactive, detached)',
      (WidgetTester tester) async {
        final fakeRepo = _FakeCalendarRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              calendarRepositoryProvider.overrideWithValue(fakeRepo),
              gmailConnectionStatusProvider.overrideWith(
                (ref) async => const GmailConnectionStatus(connected: true),
              ),
            ],
            child: const MaterialApp(home: CalendarScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(fakeRepo.upcomingCalls, 1);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
        await tester.pumpAndSettle();

        expect(
          fakeRepo.upcomingCalls,
          1,
          reason: 'Apenas o estado "resumed" deveria disparar revalidação',
        );
      },
    );
  });

  group('Erro de escopo em "Próximos eventos"', () {
    testWidgets(
      'Escopo ausente na busca de próximos eventos mostra o painel "Reconectar Gmail"',
      (WidgetTester tester) async {
        final fakeRepo = _FakeCalendarRepository()
          ..upcomingError = const CalendarScopeException();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              calendarRepositoryProvider.overrideWithValue(fakeRepo),
              gmailConnectionStatusProvider.overrideWith(
                (ref) async => const GmailConnectionStatus(connected: true),
              ),
            ],
            child: const MaterialApp(home: CalendarScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // A visão do mês carregou normalmente (lista vazia, sem erro) — só a seção "Próximos
        // eventos" está com escopo ausente — então deve haver exatamente UM painel de
        // reconexão na tela, vindo da seção de baixo.
        expect(find.text('Reconectar Gmail'), findsOneWidget);
        expect(
          find.text('Reconecte o Gmail para usar a agenda.'),
          findsOneWidget,
        );
        // A mensagem genérica antiga não deveria mais aparecer para este erro.
        expect(
          find.text('Erro ao carregar eventos. Verifique sua conexão.'),
          findsNothing,
        );
      },
    );
  });

  group('Indicação da conta Google sincronizada', () {
    testWidgets('Mostra o e-mail da conta conectada quando disponível', (
      WidgetTester tester,
    ) async {
      final fakeRepo = _FakeCalendarRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            calendarRepositoryProvider.overrideWithValue(fakeRepo),
            gmailConnectionStatusProvider.overrideWith(
              (ref) async => const GmailConnectionStatus(
                connected: true,
                gmailEmail: 'usuaria@gmail.com',
              ),
            ),
          ],
          child: const MaterialApp(home: CalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('usuaria@gmail.com'), findsOneWidget);
    });

    testWidgets('Não mostra nada enquanto o status ainda não chegou', (
      WidgetTester tester,
    ) async {
      final fakeRepo = _FakeCalendarRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            calendarRepositoryProvider.overrideWithValue(fakeRepo),
            gmailConnectionStatusProvider.overrideWith(
              (ref) async => const GmailConnectionStatus(connected: false),
            ),
          ],
          child: const MaterialApp(home: CalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Sincronizado com'), findsNothing);
    });
  });
}

/// Equivalente local ao `unawaited` de `dart:async` — evita o lint de "future não aguardado" sem
/// puxar um import extra só para isso, já que o ponto do teste é justamente NÃO esperar o
/// `Future` retornado por `RefreshIndicatorState.show()` diretamente (ele só resolve depois que a
/// animação do indicador termina de recolher; o que o teste quer aguardar é o `pumpAndSettle`
/// seguinte, que cobre tanto a animação quanto as buscas de rede).
void unawaited(Future<void> future) {}
