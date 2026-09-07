// TEMP critic harness (round 3). Not part of the product. Deleted after the audit.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

Widget harness({
  required Brightness brightness,
  required List<Object> overrides,
}) {
  return RepaintBoundary(
    key: _rootKey,
    child: ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.light
            ? sincroLightTheme
            : sincroDarkTheme,
        home: const CalendarScreen(),
      ),
    ),
  );
}

Future<ui.Image> grab(WidgetTester t) async {
  return (await t.runAsync(() async {
    final b = _rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return b.toImage(pixelRatio: 2.0);
  }))!;
}

Future<void> save(WidgetTester t, ui.Image img, String name) async {
  final bytes = await t.runAsync(() => img.toByteData(format: ui.ImageByteFormat.png));
  Directory(outDir).createSync(recursive: true);
  File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void drain(WidgetTester t, String name) {
  final errs = <Object?>[];
  while (true) {
    final e = t.takeException();
    if (e == null) break;
    errs.add(e);
  }
  // ignore: avoid_print
  print('CONSOLE[$name]: ${errs.isEmpty ? "CLEAN" : errs}');
}

CalendarEvent ev(String id, String titulo, int dia, int h, {String desc = ''}) {
  final now = DateTime.now();
  return CalendarEvent(
    id: id,
    titulo: titulo,
    descricao: desc,
    dataHoraInicio: DateTime(now.year, now.month, dia, h, 0),
    dataHoraFim: DateTime(now.year, now.month, dia, h + 1, 30),
  );
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Atkinson Hyperlegible');
    loader.addFont(File('assets/fonts/AtkinsonHyperlegible-Regular.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
    loader.addFont(File('assets/fonts/AtkinsonHyperlegible-Bold.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  });
  final now = DateTime.now();
  final eventos = [
    ev('1', 'Reuniao com a equipe de produto', now.day, 9,
        desc: 'Revisao do roadmap trimestral e prioridades da proxima sprint.'),
    ev('2', 'Consulta com a terapeuta', now.day, 14),
    ev('3', 'Almoco com Marina', now.day > 27 ? 1 : now.day + 1, 12),
  ];

  List<Object> dataOv(List<CalendarEvent> l) => [
        monthEventsProvider.overrideWith((ref, p) async => l),
        upcomingEventsProvider.overrideWith((ref) async => l),
      ];
  List<Object> loadOv() => [
        monthEventsProvider
            .overrideWith((ref, p) => Completer<List<CalendarEvent>>().future),
        upcomingEventsProvider
            .overrideWith((ref) => Completer<List<CalendarEvent>>().future),
      ];
  List<Object> errOv(Object e) => [
        monthEventsProvider.overrideWith((ref, p) => throw e),
        upcomingEventsProvider.overrideWith((ref) => throw e),
      ];

  testWidgets('critic captures', (t) async {

    Future<void> scenario(
      String name,
      Brightness b,
      Size size,
      List<Object> ov, {
      bool settle = true,
    }) async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      await t.pumpWidget(harness(brightness: b, overrides: ov));
      if (settle) {
        await t.pumpAndSettle(const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      } else {
        await t.pump(const Duration(milliseconds: 20));
        await t.pump(const Duration(milliseconds: 20));
        // ignore: avoid_print
        print('STATE[$name]: reconectar=${find.text('Reconectar Gmail').evaluate().length} '
            'tentar=${find.text('Tentar novamente').evaluate().length} '
            'generico=${find.textContaining('Erro ao carregar').evaluate().length} '
            'spinner=${find.byType(CircularProgressIndicator).evaluate().length}');
      }
      drain(t, name);
      await save(t, await grab(t), name);
    }

    for (final b in [Brightness.light, Brightness.dark]) {
      final bn = b == Brightness.light ? 'light' : 'dark';
      await scenario('data_${bn}_390', b, const Size(390, 844), dataOv(eventos));
      await scenario('empty_${bn}_390', b, const Size(390, 844), dataOv(const []));
      await scenario('loading_${bn}_390', b, const Size(390, 844), loadOv(),
          settle: false);
      await scenario('errscope_${bn}_390', b, const Size(390, 844),
          errOv(const CalendarScopeException()), settle: false);
      await scenario('errunavail_${bn}_390', b, const Size(390, 844),
          errOv(const CalendarUnavailableException()), settle: false);
      await scenario('errgeneric_${bn}_390', b, const Size(390, 844),
          errOv(StateError('boom')), settle: false);
      await scenario('data_${bn}_1440', b, const Size(1440, 900), dataOv(eventos));
      await scenario('empty_${bn}_1440', b, const Size(1440, 900), dataOv(const []));
    }
    await scenario('data_light_320', Brightness.light, const Size(320, 800),
        dataOv(eventos));
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  testWidgets('critic focus ring', (t) async {

    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(
        harness(brightness: Brightness.light, overrides: dataOv(eventos)));
    await t.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));

    final grid = find.byType(GridView).at(1);
    final cells = find.descendant(of: grid, matching: find.byType(InkWell));
    Rect rectFor(int dia) {
      final txt = find.descendant(of: grid, matching: find.text('$dia'));
      final c = t.getRect(txt).center;
      for (final e in cells.evaluate()) {
        final r = t.getRect(find.byWidget(e.widget));
        if (r.contains(c)) return r;
      }
      throw StateError('cell $dia not found');
    }

    final hoje = now.day;
    final outro = hoje == 1 ? 2 : hoje - 1;
    final rHoje = rectFor(hoje);
    final rOutro = rectFor(outro);
    // ignore: avoid_print
    print('CELL today=$rHoje other=$rOutro');

    Future<Uint8List> raw() async {
      final img = await grab(t);
      final bd = await t.runAsync(() => img.toByteData(format: ui.ImageByteFormat.rawRgba));
      return bd!.buffer.asUint8List();
    }

    final w = (390 * 2).toInt();
    int diffIn(Uint8List a, Uint8List b, Rect r) {
      int n = 0;
      for (int y = (r.top * 2).floor(); y < (r.bottom * 2).ceil(); y++) {
        for (int x = (r.left * 2).floor(); x < (r.right * 2).ceil(); x++) {
          final i = (y * w + x) * 4;
          if (i + 3 >= a.length) continue;
          if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
        }
      }
      return n;
    }

    final base = await raw();
    await save(t, await grab(t), 'focus_none');

    // Tab through the tree, recording which cell (if any) becomes focused.
    int? tabsToToday;
    int? tabsToOther;
    for (int i = 1; i <= 60; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle(const Duration(milliseconds: 50),
          EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
      final f = FocusManager.instance.primaryFocus;
      final fr = f?.rect;
      if (fr == null) continue;
      if (tabsToOther == null && (fr.center - rOutro.center).distance < 2) {
        tabsToOther = i;
        final after = await raw();
        await save(t, await grab(t), 'focus_other_day');
        // ignore: avoid_print
        print('FOCUS other-day cell after $i tabs; changed px in cell = '
            '${diffIn(base, after, rOutro)}');
      }
      if (tabsToToday == null && (fr.center - rHoje.center).distance < 2) {
        tabsToToday = i;
        final after = await raw();
        await save(t, await grab(t), 'focus_today');
        // ignore: avoid_print
        print('FOCUS today cell after $i tabs; changed px in cell = '
            '${diffIn(base, after, rHoje)}');
      }
      if (tabsToToday != null && tabsToOther != null) break;
    }
    // ignore: avoid_print
    print('TABS today=$tabsToToday other=$tabsToOther');
    drain(t, 'focus');
  });
}
