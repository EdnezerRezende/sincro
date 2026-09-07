// TEMP critic harness (round 3). Not part of the product. Deleted after the audit.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';

const outDir =
    '/private/tmp/claude-501/-Users-ed-Desenvolvimento-projetos-sincro/9c595fdb-092a-49b5-bffd-51ad092779ba/scratchpad/r3';

final _rootKey = GlobalKey();

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
      descricao: 'Pauta curta',
      dataHoraInicio: DateTime(now.year, now.month, now.day, 9),
      dataHoraFim: DateTime(now.year, now.month, now.day, 10),
    ),
  ];
  List<Object> dataOv() => [
        monthEventsProvider.overrideWith((ref, p) async => eventos),
        upcomingEventsProvider.overrideWith((ref) async => eventos),
      ];

  testWidgets('tap + keyboard activate a day cell', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(harness(Brightness.light, dataOv()));
    await t.pumpAndSettle();

    final grid = find.byType(GridView).at(1);
    final cells = find.descendant(of: grid, matching: find.byType(InkWell));
    final rects = <Rect>[];
    for (final e in cells.evaluate()) {
      rects.add(t.getRect(find.byWidget(e.widget)));
    }
    // ignore: avoid_print
    print('DAY CELLS = ${rects.length}; first=${rects.first}');

    // 1) real tap on today's cell
    final todayTxt = find.descendant(of: grid, matching: find.text('${now.day}'));
    await t.tap(todayTxt);
    await t.pumpAndSettle();
    // ignore: avoid_print
    print('TAP sheet = ${find.textContaining('Eventos do dia').evaluate().length}');
    await save(t, 'sheet_light');
    if (find.textContaining('Eventos do dia').evaluate().isNotEmpty) {
      Navigator.of(t.element(find.byType(CalendarScreen))).pop();
      await t.pumpAndSettle();
    }

    // 2) keyboard: tab until a day cell holds focus, then Enter
    int tabs = 0;
    Rect? focused;
    for (int i = 1; i <= 60; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      final r = FocusManager.instance.primaryFocus?.rect;
      if (r == null) continue;
      final hit = rects.where((c) => (c.center - r.center).distance < 1.5);
      if (hit.isNotEmpty) {
        tabs = i;
        focused = hit.first;
        break;
      }
    }
    // ignore: avoid_print
    print('KBD focused day cell after $tabs tabs: $focused');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    // ignore: avoid_print
    print('ENTER sheet = ${find.textContaining('Eventos do dia').evaluate().length}');
    if (find.textContaining('Eventos do dia').evaluate().isEmpty) {
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      // ignore: avoid_print
      print('SPACE sheet = ${find.textContaining('Eventos do dia').evaluate().length}');
    }
    await save(t, 'kbd_after_enter');
  });

  testWidgets('sheet in dark mode', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(harness(Brightness.dark, dataOv()));
    await t.pumpAndSettle();
    await t.tap(find.descendant(
        of: find.byType(GridView).at(1), matching: find.text('${now.day}')));
    await t.pumpAndSettle();
    await save(t, 'sheet_dark');
    // empty day
    Navigator.of(t.element(find.byType(CalendarScreen))).pop();
    await t.pumpAndSettle();
    final vazio = now.day == 20 ? 21 : 20;
    await t.tap(find.descendant(
        of: find.byType(GridView).at(1), matching: find.text('$vazio')));
    await t.pumpAndSettle();
    // ignore: avoid_print
    print('EMPTY DAY sheet = ${find.textContaining('Nenhum evento neste dia').evaluate().length}');
    await save(t, 'sheet_dark_empty');
  });
}
