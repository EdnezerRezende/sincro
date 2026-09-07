// TEMP critic harness (round 3). Not part of the product. Deleted after the audit.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_repository.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';

const outDir =
    '/private/tmp/claude-501/-Users-ed-Desenvolvimento-projetos-sincro/9c595fdb-092a-49b5-bffd-51ad092779ba/scratchpad/r3';

final _rootKey = GlobalKey();

class HangingRepo extends CalendarRepository {
  HangingRepo() : super(Dio());
  @override
  Future<CalendarEvent> createEvent({
    required String titulo,
    required String descricao,
    required DateTime dataHoraInicio,
    required DateTime dataHoraFim,
    bool ehDiaInteiro = false,
  }) => Completer<CalendarEvent>().future;
}

Widget harness(Brightness b, List<Object> ov) => RepaintBoundary(
      key: _rootKey,
      child: ProviderScope(
        overrides: ov.cast(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: b == Brightness.light ? sincroLightTheme : sincroDarkTheme,
          home: const CalendarScreen(),
        ),
      ),
    );

Future<void> save(WidgetTester t, String name) async {
  final img = (await t.runAsync(() async {
    final bd =
        _rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return bd.toImage(pixelRatio: 2.0);
  }))!;
  final bytes =
      await t.runAsync(() => img.toByteData(format: ui.ImageByteFormat.png));
  Directory(outDir).createSync(recursive: true);
  File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    final l = FontLoader('Atkinson Hyperlegible');
    l.addFont(File('assets/fonts/AtkinsonHyperlegible-Regular.ttf')
        .readAsBytes()
        .then((b) => ByteData.view(b.buffer)));
    l.addFont(File('assets/fonts/AtkinsonHyperlegible-Bold.ttf')
        .readAsBytes()
        .then((b) => ByteData.view(b.buffer)));
    await l.load();
  });

  final now = DateTime.now();
  final eventos = [
    CalendarEvent(
      id: '1',
      titulo: 'Reuniao com a equipe',
      descricao: '',
      dataHoraInicio: DateTime(now.year, now.month, now.day, 9),
      dataHoraFim: DateTime(now.year, now.month, now.day, 10),
    ),
  ];

  List<Object> dataOv(List<CalendarEvent> l) => [
        monthEventsProvider.overrideWith((ref, p) async => l),
        upcomingEventsProvider.overrideWith((ref) async => l),
      ];

  testWidgets('how long until the real error panel appears', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(harness(Brightness.light, [
      monthEventsProvider
          .overrideWith((ref, p) => throw const CalendarScopeException()),
      upcomingEventsProvider
          .overrideWith((ref) => throw const CalendarScopeException()),
    ]));
    await t.pump();

    Duration elapsed = Duration.zero;
    Duration? aparece;
    for (int i = 0; i < 200; i++) {
      if (find.text('Reconectar Gmail').evaluate().isNotEmpty) {
        aparece = elapsed;
        break;
      }
      await t.pump(const Duration(milliseconds: 500));
      elapsed += const Duration(milliseconds: 500);
    }
    // ignore: avoid_print
    print('SCOPE ERROR panel appeared after: '
        '${aparece == null ? "NEVER within 100s" : "${aparece.inMilliseconds} ms"} '
        '(spinners now: ${find.byType(CircularProgressIndicator).evaluate().length})');
    if (aparece != null) await save(t, 'errscope_light_390_real');
    // drain retry timers
    for (int i = 0; i < 40; i++) {
      await t.pump(const Duration(seconds: 2));
    }
    while (t.takeException() != null) {}
  });

  testWidgets('semantics of a day cell', (t) async {
    final handle = t.ensureSemantics();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(harness(Brightness.light, dataOv(eventos)));
    await t.pumpAndSettle();

    final node = t.getSemantics(find.bySemanticsLabel(RegExp(r'^1 de ')));
    // ignore: avoid_print
    print('SEM label="${node.label}" button=${node.hasFlag(SemanticsFlag.isButton)} '
        'tap=${node.getSemanticsData().hasAction(SemanticsAction.tap)} '
        'focusable=${node.hasFlag(SemanticsFlag.isFocusable)}');
    final hoje = t.getSemantics(find.bySemanticsLabel(RegExp('^${now.day} de ')));
    // ignore: avoid_print
    print('SEM today label="${hoje.label}" button=${hoje.hasFlag(SemanticsFlag.isButton)} '
        'tap=${hoje.getSemanticsData().hasAction(SemanticsAction.tap)}');
    handle.dispose();
  });

  testWidgets('keyboard activation of a day cell', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(harness(Brightness.light, dataOv(eventos)));
    await t.pumpAndSettle();

    for (int i = 0; i < 12; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      final f = FocusManager.instance.primaryFocus;
      if (f?.rect != null && f!.rect.height == 48) {
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        break;
      }
    }
    // ignore: avoid_print
    print('KEYBOARD sheet open = '
        '${find.textContaining('Eventos do dia').evaluate().length}');
    await save(t, 'keyboard_sheet');
  });

  testWidgets('dialog + saving spinner shape', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    for (final b in [Brightness.light, Brightness.dark]) {
      final bn = b == Brightness.light ? 'light' : 'dark';
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await t.pumpWidget(harness(b, [
        ...dataOv(eventos),
        calendarRepositoryProvider.overrideWithValue(HangingRepo()),
      ]));
      await t.pumpAndSettle();
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      await save(t, 'dialog_$bn');
      // ignore: avoid_print
      print('DIALOG[$bn] salvar=${find.text('Salvar').evaluate().length}');

      await t.enterText(find.byType(TextField).first, 'Novo evento de teste');
      await t.pumpAndSettle();
      await t.tap(find.text('Salvar'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final cpi = find.descendant(
        of: find.byType(ElevatedButton),
        matching: find.byType(CircularProgressIndicator),
      );
      if (cpi.evaluate().isNotEmpty) {
        final s = t.getSize(cpi);
        // ignore: avoid_print
        print('SAVING spinner size[$bn] = $s');
        await save(t, 'dialog_saving_$bn');
      } else {
        // ignore: avoid_print
        print('SAVING spinner[$bn] NOT FOUND');
        await save(t, 'dialog_after_save_$bn');
      }
      while (t.takeException() != null) {}
    }
  });
}
