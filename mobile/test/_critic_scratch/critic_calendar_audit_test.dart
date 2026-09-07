import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/calendar/calendar_screen.dart';
import 'package:sincro_mobile/features/calendar/calendar_providers.dart';
import 'package:sincro_mobile/features/calendar/calendar_event.dart';

List<CalendarEvent> _sample() {
  final now = DateTime.now();
  return [
    CalendarEvent(
      id: '1', titulo: 'Consulta com a terapeuta', descricao: 'Levar o caderno de anotacoes',
      dataHoraInicio: DateTime(now.year, now.month, now.day, 14, 30),
      dataHoraFim: DateTime(now.year, now.month, now.day, 15, 30),
    ),
    CalendarEvent(
      id: '2', titulo: 'Reuniao de equipe', descricao: '',
      dataHoraInicio: DateTime(now.year, now.month, now.day + 1, 9, 0),
      dataHoraFim: DateTime(now.year, now.month, now.day + 1, 10, 0),
    ),
  ];
}

Widget _app({
  required ThemeData theme,
  required Future<List<CalendarEvent>> Function() upcoming,
  required Future<List<CalendarEvent>> Function() month,
}) {
  return ProviderScope(
    overrides: [
      upcomingEventsProvider.overrideWith((ref) => upcoming()),
      monthEventsProvider.overrideWith((ref, p) => month()),
    ],
    child: RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(theme: theme, home: const CalendarScreen()),
    ),
  );
}

Future<void> _shot(WidgetTester t, String name) async {
  final b = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  final img = b.toImageSync(pixelRatio: 2.0);
  final bd = await img.toByteData(format: ImageByteFormat.png);
  final f = File('/private/tmp/claude-501/-Users-ed-Desenvolvimento-projetos-sincro/9c595fdb-092a-49b5-bffd-51ad092779ba/scratchpad/$name.png');
  f.writeAsBytesSync(bd!.buffer.asUint8List());
  // ignore: avoid_print
  print('SHOT $name -> ${f.lengthSync()} bytes');
}

void main() {
  testWidgets('MEASURE day-cell tap target at 390px', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(_app(theme: sincroLightTheme, upcoming: () async => _sample(), month: () async => _sample()));
    await t.pumpAndSettle();

    final inkwells = find.byType(InkWell);
    print('InkWell count: ${inkwells.evaluate().length}');
    final sizes = <Size>{};
    for (final e in inkwells.evaluate()) {
      final ro = e.renderObject as RenderBox;
      sizes.add(ro.size);
    }
    print('Distinct day-cell sizes: $sizes');
    for (final s in sizes) {
      print('  cell ${s.width} x ${s.height} -> ${s.width >= 48 && s.height >= 48 ? "PASS" : "FAIL <48dp"}');
    }
  });

  testWidgets('SEMANTICS audit of day cells', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final handle = t.ensureSemantics();

    await t.pumpWidget(_app(theme: sincroLightTheme, upcoming: () async => _sample(), month: () async => _sample()));
    await t.pumpAndSettle();

    final nodes = <SemanticsNode>[];
    void walk(SemanticsNode n) {
      nodes.add(n);
      n.visitChildren((c) { walk(c); return true; });
    }
    walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);

    print('--- nodes with tap action ---');
    for (final n in nodes) {
      final d = n.getSemanticsData();
      if (d.hasAction(SemanticsAction.tap)) {
        print('label="${d.label}" tooltip="${d.tooltip}" isButton=${d.hasFlag(SemanticsFlag.isButton)} rect=${n.rect.width.toStringAsFixed(1)}x${n.rect.height.toStringAsFixed(1)}');
      }
    }
    handle.dispose();
  });

  testWidgets('CAPTURE light 390 populated', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(theme: sincroLightTheme, upcoming: () async => _sample(), month: () async => _sample()));
    await t.pumpAndSettle();
    await _shot(t, 'cal_light_390');
  });

  testWidgets('CAPTURE dark 390 populated', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(theme: sincroDarkTheme, upcoming: () async => _sample(), month: () async => _sample()));
    await t.pumpAndSettle();
    await _shot(t, 'cal_dark_390');
  });

  testWidgets('CAPTURE light 1440 populated', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(theme: sincroLightTheme, upcoming: () async => _sample(), month: () async => _sample()));
    await t.pumpAndSettle();
    await _shot(t, 'cal_light_1440');
    // measure cells at 1440
    for (final e in find.byType(InkWell).evaluate().take(1)) {
      print('1440 cell size: ${(e.renderObject as RenderBox).size}');
    }
  });

  testWidgets('CAPTURE empty state', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(theme: sincroLightTheme, upcoming: () async => <CalendarEvent>[], month: () async => <CalendarEvent>[]));
    await t.pumpAndSettle();
    await _shot(t, 'cal_empty_390');
  });

  testWidgets('CAPTURE loading state', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(theme: sincroLightTheme, upcoming: () async => Completer<List<CalendarEvent>>().future, month: () async => Completer<List<CalendarEvent>>().future));
    await t.pump(const Duration(milliseconds: 100));
    await _shot(t, 'cal_loading_390');
  });

  testWidgets('CAPTURE error state (generic)', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(theme: sincroLightTheme, upcoming: () async => throw Exception('boom'), month: () async => throw Exception('boom')));
    await t.pumpAndSettle();
    await _shot(t, 'cal_error_390');
  });
}
