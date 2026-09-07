
// GAUNTLET CRITIC SCRATCH HARNESS - not part of the product. Delete after the run.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/auth/auth_providers.dart';
import 'package:sincro_mobile/features/auth/auth_service.dart';
import 'package:sincro_mobile/features/auth/login_screen.dart';

const outDir =
    '/private/tmp/claude-501/-Users-ed-Desenvolvimento-projetos-sincro/9c595fdb-092a-49b5-bffd-51ad092779ba/scratchpad/shots';

class FakeAuthService extends Mock implements AuthService {}

Future<void> loadRealFonts() async {
  for (final f in [
    'assets/fonts/AtkinsonHyperlegible-Regular.ttf',
    'assets/fonts/AtkinsonHyperlegible-Bold.ttf',
  ]) {
    final loader = FontLoader('Atkinson Hyperlegible');
    loader.addFont(rootBundle.load(f));
    await loader.load();
  }
}

Widget app(ThemeData theme, AuthService svc, {double scale = 1.0}) {
  return ProviderScope(
    overrides: [authServiceProvider.overrideWithValue(svc)],
    child: MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
}

final Map<String, dynamic> report = {};

void dumpGeometry(WidgetTester tester, String tag) {
  final m = <String, dynamic>{};
  Rect? r(Finder f, [int i = 0]) {
    try {
      final e = f.evaluate().toList();
      if (e.length <= i) return null;
      return tester.getRect(find.byWidget(e[i].widget));
    } catch (_) {
      return null;
    }
  }

  void put(String k, Rect? rect) {
    if (rect != null) {
      m[k] = {'l': rect.left, 't': rect.top, 'r': rect.right, 'b': rect.bottom,
              'w': rect.width, 'h': rect.height};
    }
  }

  final inputs = find.byType(TextFormField).evaluate().toList();
  for (var i = 0; i < inputs.length; i++) {
    put('input$i', tester.getRect(find.byWidget(inputs[i].widget)));
  }
  final ebs = find.byType(ElevatedButton).evaluate().toList();
  for (var i = 0; i < ebs.length; i++) {
    put('elevatedButton$i', tester.getRect(find.byWidget(ebs[i].widget)));
  }
  put('checkbox', r(find.byType(Checkbox)));
  put('textButton', r(find.byType(TextButton)));
  final divs = find.byType(Divider).evaluate().toList();
  for (var i = 0; i < divs.length; i++) {
    put('divider$i', tester.getRect(find.byWidget(divs[i].widget)));
  }
  // any overflow?
  m['surface'] = {'w': tester.binding.platformDispatcher.views.first.physicalSize.width};
  report[tag] = m;
}

Future<void> shoot(WidgetTester tester, String name) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$outDir/$name.png')));
}

void main() {
  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue('');
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('GEOMETRY_JSON_START');
    // ignore: avoid_print
    print(jsonEncode(report));
    // ignore: avoid_print
    print('GEOMETRY_JSON_END');
  });

  testWidgets('idle light 390', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final svc = FakeAuthService();
    await tester.pumpWidget(app(sincroLightTheme, svc));
    await tester.pumpAndSettle();
    dumpGeometry(tester, 'idle_light_390');
    await shoot(tester, 'login_idle_light_390');
  });

  testWidgets('idle dark 390', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final svc = FakeAuthService();
    await tester.pumpWidget(app(sincroDarkTheme, svc));
    await tester.pumpAndSettle();
    dumpGeometry(tester, 'idle_dark_390');
    await shoot(tester, 'login_idle_dark_390');
  });

  testWidgets('idle light 1440', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final svc = FakeAuthService();
    await tester.pumpWidget(app(sincroLightTheme, svc));
    await tester.pumpAndSettle();
    dumpGeometry(tester, 'idle_light_1440');
    await shoot(tester, 'login_idle_light_1440');
  });

  testWidgets('idle dark 1440', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final svc = FakeAuthService();
    await tester.pumpWidget(app(sincroDarkTheme, svc));
    await tester.pumpAndSettle();
    dumpGeometry(tester, 'idle_dark_1440');
    await shoot(tester, 'login_idle_dark_1440');
  });

  testWidgets('error light 390', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final svc = FakeAuthService();
    when(() => svc.logIn(any(), any())).thenThrow(Exception('boom'));
    await tester.pumpWidget(app(sincroLightTheme, svc));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('inválidos'), findsOneWidget);
    dumpGeometry(tester, 'error_light_390');
    await shoot(tester, 'login_error_light_390');
  });

  testWidgets('error dark 390', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final svc = FakeAuthService();
    when(() => svc.logIn(any(), any())).thenThrow(Exception('boom'));
    await tester.pumpWidget(app(sincroDarkTheme, svc));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    dumpGeometry(tester, 'error_dark_390');
    await shoot(tester, 'login_error_dark_390');
  });

  testWidgets('loading light 390 (Entrar loading, Google disabled)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final svc = FakeAuthService();
    when(() => svc.logIn(any(), any()))
        .thenAnswer((_) => Future.delayed(const Duration(seconds: 30)));
    await tester.pumpWidget(app(sincroLightTheme, svc));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // assert both buttons are now disabled
    final ebs = tester.widgetList<ElevatedButton>(find.byType(ElevatedButton)).toList();
    // ignore: avoid_print
    print('LOADING_BTN_ENABLED: ${ebs.map((e) => e.onPressed != null).toList()}');
    expect(ebs.every((e) => e.onPressed == null), isTrue,
        reason: 'both buttons must be disabled while loading');
    dumpGeometry(tester, 'loading_light_390');
    await shoot(tester, 'login_loading_light_390');
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
  });

  testWidgets('loading dark 390', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final svc = FakeAuthService();
    when(() => svc.logIn(any(), any()))
        .thenAnswer((_) => Future.delayed(const Duration(seconds: 30)));
    await tester.pumpWidget(app(sincroDarkTheme, svc));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await shoot(tester, 'login_loading_dark_390');
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
  });

  testWidgets('focus visible: tab into email + password', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final svc = FakeAuthService();
    await tester.pumpWidget(app(sincroLightTheme, svc));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await shoot(tester, 'login_focus_email_light_390');
    // keyboard traversal
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await shoot(tester, 'login_focus_next_light_390');
  });

  testWidgets('text scale 2.0 light 390', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final svc = FakeAuthService();
    when(() => svc.logIn(any(), any())).thenThrow(Exception('boom'));
    await tester.pumpWidget(app(sincroLightTheme, svc, scale: 2.0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    dumpGeometry(tester, 'scale2_light_390');
    await shoot(tester, 'login_scale2_light_390');
  });

  testWidgets('text scale 1.5 light 390', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final svc = FakeAuthService();
    await tester.pumpWidget(app(sincroLightTheme, svc, scale: 1.5));
    await tester.pumpAndSettle();
    dumpGeometry(tester, 'scale15_light_390');
    await shoot(tester, 'login_scale15_light_390');
  });
}

