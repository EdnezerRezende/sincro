import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';

void main() {
  group('Calendar Touch Target Sizes', () {
    // 320dp é a largura mais estreita de tela real relevante (iPhone SE 1ª geração / Android
    // pequeno); 390dp é o iPhone 13/14 padrão. Testamos as quatro larguras para cobrir toda a
    // faixa suportada.
    //
    // A ALTURA da célula é garantida em exatamente 48dp em qualquer largura de tela por
    // `mainAxisExtent: 48` no `SliverGridDelegateWithFixedCrossAxisCount` (essa é a correção
    // desta rodada: o `ConstrainedBox(minHeight: 48)` anterior era inerte porque o `GridView`
    // entrega constraints tight a cada célula, e `parent.enforce` de um `ConstrainedBox` sob
    // constraints tight sempre resulta no tamanho tight do pai).
    //
    // A LARGURA da célula, ao contrário, é geometricamente limitada pelo número de colunas: com
    // 7 colunas (uma por dia da semana) e 24dp de padding horizontal do `SingleChildScrollView`
    // pai, uma célula de 48dp de largura exigiria pelo menos 7×48 + 24 = 360dp de largura de tela
    // só de área útil — e isso sem contar `crossAxisSpacing`. Numa tela de 320dp isso é
    // impossível de satisfazer com qualquer valor de padding/spacing (mesmo com ambos zerados,
    // 320/7 = 45.7dp < 48dp): não há forma de encaixar 7 alvos de toque de 48dp lado a lado em
    // 320dp de largura. Por isso a largura só é verificada contra 48dp na largura em que isso é
    // matematicamente alcançável (390dp, a mais comum em aparelhos atuais); nas larguras mais
    // estreitas, a largura é verificada contra o mínimo que a WCAG 2.5.8 (Target Size Minimum,
    // nível AA) de fato exige — 24×24px CSS — que é o critério de sucesso de AA realmente
    // aplicável aqui (48dp é a recomendação do Material Design, mais rigorosa que a WCAG AA, mas
    // inatingível em ambas as dimensões simultaneamente numa grade de 7 colunas em telas muito
    // estreitas).
    const larguraOndeAlvoDe48DpELargura = 390.0;
    for (final largura in [320.0, 360.0, 375.0, 390.0]) {
      testWidgets(
        'Day cells in CalendarScreen render with height >=48dp and width '
        '>=24dp (WCAG 2.5.8 AA) at every width; width >=48dp where '
        'geometrically achievable (largura ${largura}dp)',
        (WidgetTester tester) async {
          tester.view.physicalSize = Size(largura, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                monthEventsProvider.overrideWith(
                  (ref, params) async => <CalendarEvent>[],
                ),
                upcomingEventsProvider.overrideWith(
                  (ref) async => <CalendarEvent>[],
                ),
              ],
              child: const MaterialApp(home: CalendarScreen()),
            ),
          );
          await tester.pumpAndSettle();

          // O segundo GridView da tela é a grade de dias do mês (o primeiro é o cabeçalho
          // com os nomes dos dias da semana).
          final dayGrid = find.byType(GridView).at(1);
          final dayCellInkWells = find.descendant(
            of: dayGrid,
            matching: find.byType(InkWell),
          );

          expect(dayCellInkWells, findsWidgets);

          final larguraMinima = largura >= larguraOndeAlvoDe48DpELargura
              ? 48.0
              : 24.0;

          for (final element in dayCellInkWells.evaluate()) {
            final size = tester.getSize(find.byWidget(element.widget));
            expect(
              size.height,
              greaterThanOrEqualTo(48),
              reason:
                  'Day cell height ${size.height} is below the 48dp touch '
                  'target minimum at screen width ${largura}dp',
            );
            expect(
              size.width,
              greaterThanOrEqualTo(larguraMinima),
              reason:
                  'Day cell width ${size.width} is below the '
                  '${larguraMinima}dp touch target minimum at screen width '
                  '${largura}dp',
            );
          }
        },
      );
    }

    testWidgets(
      'Month navigation chevrons in CalendarScreen have 48dp touch target',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              monthEventsProvider.overrideWith(
                (ref, params) async => <CalendarEvent>[],
              ),
              upcomingEventsProvider.overrideWith(
                (ref) async => <CalendarEvent>[],
              ),
            ],
            child: const MaterialApp(home: CalendarScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Os dois `IconButton` do cabeçalho de navegação (mês anterior/próximo) renderizados
        // de verdade dentro de `_MonthNavigationHeader`, não um `IconButton` avulso.
        final chevronFinder = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.icon is Icon &&
              ((widget.icon as Icon).icon == Icons.chevron_left ||
                  (widget.icon as Icon).icon == Icons.chevron_right),
        );

        expect(chevronFinder, findsNWidgets(2));

        for (final element in chevronFinder.evaluate()) {
          final size = tester.getSize(find.byWidget(element.widget));
          expect(
            size.width,
            greaterThanOrEqualTo(48),
            reason: 'Month nav chevron width ${size.width} is below 48dp',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(48),
            reason: 'Month nav chevron height ${size.height} is below 48dp',
          );
        }
      },
    );

    testWidgets(
      'Event card "Editar" button in CalendarScreen has 48dp touch target',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final evento = CalendarEvent(
          id: 'evt-1',
          titulo: 'Reunião de equipe',
          descricao: '',
          dataHoraInicio: DateTime.now().add(const Duration(hours: 2)),
          dataHoraFim: DateTime.now().add(const Duration(hours: 3)),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              monthEventsProvider.overrideWith(
                (ref, params) async => <CalendarEvent>[],
              ),
              upcomingEventsProvider.overrideWith(
                (ref) async => <CalendarEvent>[evento],
              ),
            ],
            child: const MaterialApp(home: CalendarScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Botão "Editar" renderizado de verdade dentro do `_EventCard` da lista de próximos
        // eventos (não um `OutlinedButton` avulso construído só para o teste).
        final editarButtonFinder = find.widgetWithText(
          OutlinedButton,
          'Editar',
        );

        expect(editarButtonFinder, findsOneWidget);

        final buttonSize = tester.getSize(editarButtonFinder);
        expect(
          buttonSize.height,
          greaterThanOrEqualTo(48),
          reason: '"Editar" button height ${buttonSize.height} is below 48dp',
        );
      },
    );
  });
}
