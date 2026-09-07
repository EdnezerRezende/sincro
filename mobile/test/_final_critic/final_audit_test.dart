import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/core/widgets/app_button.dart';

int _c8(double v) => (v * 255).round();

String hx(Color? c) {
  if (c == null) return 'NULL';
  return ('#'
          '${_c8(c.a).toRadixString(16).padLeft(2, '0')}'
          '${_c8(c.r).toRadixString(16).padLeft(2, '0')}'
          '${_c8(c.g).toRadixString(16).padLeft(2, '0')}'
          '${_c8(c.b).toRadixString(16).padLeft(2, '0')}')
      .toUpperCase();
}

double _lin(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
double lum(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

Widget host(Widget child, {required bool dark}) {
  return MaterialApp(
    theme: dark ? sincroDarkTheme : sincroLightTheme,
    home: Scaffold(
      body: Center(child: RepaintBoundary(key: const ValueKey('rb'), child: child)),
    ),
  );
}

ButtonStyle styleOf(WidgetTester t) =>
    t.widget<ElevatedButton>(find.byType(ElevatedButton)).style!;

void main() {
  const variants = AppButtonVariant.values;

  testWidgets('CHECK A/D — overlayColor focused per variant, light+dark', (t) async {
    for (final dark in [false, true]) {
      for (final v in variants) {
        await t.pumpWidget(host(AppButton(label: 'X', onPressed: () {}, variant: v), dark: dark));
        final s = styleOf(t);
        final focused = s.overlayColor!.resolve({WidgetState.focused});
        final scheme = Theme.of(t.element(find.byType(ElevatedButton))).colorScheme;
        // ignore: avoid_print
        print('OVERLAY focused | dark=$dark | ${v.name} => ${hx(focused)}  '
            '[primary=${hx(scheme.primary)} onPrimary=${hx(scheme.onPrimary)} '
            'onSecondary=${hx(scheme.onSecondary)}]');
        if (v == AppButtonVariant.text || v == AppButtonVariant.outline) {
          expect(focused, scheme.primary.withAlpha(30));
        } else if (v == AppButtonVariant.secondary) {
          expect(focused, scheme.onSecondary.withAlpha(30));
        } else {
          expect(focused, scheme.onPrimary.withAlpha(30));
        }
        expect(_c8(focused!.a), 30);
      }
    }
  });

  testWidgets('CHECK B/C — resolved SHAPE focused vs idle per variant', (t) async {
    for (final dark in [false, true]) {
      for (final v in variants) {
        await t.pumpWidget(host(AppButton(label: 'X', onPressed: () {}, variant: v), dark: dark));
        final s = styleOf(t);
        final scheme = Theme.of(t.element(find.byType(ElevatedButton))).colorScheme;
        final f = s.shape!.resolve({WidgetState.focused}) as RoundedRectangleBorder;
        final idle = s.shape!.resolve(<WidgetState>{}) as RoundedRectangleBorder;
        // ignore: avoid_print
        print('SHAPE | dark=$dark | ${v.name} | FOCUSED ${hx(f.side.color)} w=${f.side.width} '
            '|| IDLE ${hx(idle.side.color)} w=${idle.side.width}');
        if (v == AppButtonVariant.outline) {
          expect(f.side.color, scheme.primary);
          expect(f.side.width, 2.5);
        }
        if (v == AppButtonVariant.text) {
          expect(f.side.color, scheme.primary);
          expect(f.side.width, greaterThanOrEqualTo(2.0));
        }
      }
    }
  });

  testWidgets('CHECK B-real — focused border reaches the PAINTED Material', (t) async {
    for (final v in [AppButtonVariant.text, AppButtonVariant.outline, AppButtonVariant.primary]) {
      for (final dark in [false, true]) {
        await t.pumpWidget(host(AppButton(label: 'Focar', onPressed: () {}, variant: v), dark: dark));
        await t.pump(const Duration(milliseconds: 400));
        RoundedRectangleBorder? before;
        for (final m in t.widgetList<Material>(find.descendant(
            of: find.byType(ElevatedButton), matching: find.byType(Material)))) {
          if (m.shape is RoundedRectangleBorder) before = m.shape as RoundedRectangleBorder;
        }
        FocusScope.of(t.element(find.byType(ElevatedButton))).nextFocus();
        await t.pump(const Duration(milliseconds: 400));
        RoundedRectangleBorder? after;
        for (final m in t.widgetList<Material>(find.descendant(
            of: find.byType(ElevatedButton), matching: find.byType(Material)))) {
          if (m.shape is RoundedRectangleBorder) after = m.shape as RoundedRectangleBorder;
        }
        final focused = Focus.of(t.element(find.byType(ElevatedButton)), scopeOk: true).hasFocus;
        // ignore: avoid_print
        print('PAINTED | dark=$dark | ${v.name} | idle side=${hx(before?.side.color)} '
            'w=${before?.side.width} -> FOCUSED side=${hx(after?.side.color)} '
            'w=${after?.side.width} (anyFocus=$focused)');
      }
    }
  });

  testWidgets('CHECK B-pixel — real pixels change on focus (text + outline)', (t) async {
    Future<Uint8List> shot(AppButtonVariant v, bool focus, bool dark) async {
      await t.pumpWidget(host(
        AppButton(label: 'Focar', onPressed: () {}, variant: v, size: AppButtonSize.large),
        dark: dark,
      ));
      await t.pump(const Duration(milliseconds: 400));
      if (focus) {
        FocusScope.of(t.element(find.byType(ElevatedButton))).nextFocus();
        await t.pump(const Duration(milliseconds: 400));
      }
      final rb = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('rb')));
      final img = await rb.toImage(pixelRatio: 3.0);
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bd!.buffer.asUint8List();
    }

    for (final v in [AppButtonVariant.text, AppButtonVariant.outline, AppButtonVariant.primary]) {
      for (final dark in [false, true]) {
        final a = await shot(v, false, dark);
        final b = await shot(v, true, dark);
        var diff = 0;
        final n = math.min(a.length, b.length);
        for (var i = 0; i < n; i++) {
          if (a[i] != b[i]) diff++;
        }
        // ignore: avoid_print
        print('PIXELS | dark=$dark | ${v.name} | bytes=$n differing=$diff '
            '(${(100 * diff / n).toStringAsFixed(2)}%)');
        expect(diff, greaterThan(0), reason: '${v.name} focus must be visible');
      }
    }
  });

  testWidgets('CHECK E — disabled outline foreground luminance', (t) async {
    for (final dark in [false, true]) {
      await t.pumpWidget(host(
        const AppButton(label: 'X', onPressed: null, variant: AppButtonVariant.outline),
        dark: dark,
      ));
      final s = styleOf(t);
      final fg = s.foregroundColor!.resolve({WidgetState.disabled})!;
      final txt = t.widget<Text>(find.text('X')).style!.color!;
      final scheme = Theme.of(t.element(find.byType(ElevatedButton))).colorScheme;
      // ignore: avoid_print
      print('DISABLED OUTLINE FG | dark=$dark | style=${hx(fg)} L=${lum(fg).toStringAsFixed(4)} '
          '| textPainted=${hx(txt)} L=${lum(txt).toStringAsFixed(4)} '
          '| enabled(secondary)=${hx(scheme.secondary)} L=${lum(scheme.secondary).toStringAsFixed(4)} '
          '| onSurfaceVariant=${hx(scheme.onSurfaceVariant)} L=${lum(scheme.onSurfaceVariant).toStringAsFixed(4)}');
      if (dark) {
        expect(fg, const Color(0xFF66605A));
        expect(txt, const Color(0xFF66605A));
        expect(lum(fg), lessThan(0.4174));
        expect(lum(fg), lessThan(lum(scheme.secondary)));
      }
    }
  });

  testWidgets('CHECK F — disabled fill per variant', (t) async {
    for (final dark in [false, true]) {
      for (final v in variants) {
        await t.pumpWidget(host(AppButton(label: 'X', onPressed: null, variant: v), dark: dark));
        final bg = styleOf(t).backgroundColor!.resolve({WidgetState.disabled});
        // ignore: avoid_print
        print('DISABLED BG | dark=$dark | ${v.name} => ${hx(bg)}');
        if (v == AppButtonVariant.outline) {
          expect(bg, Colors.transparent);
        } else {
          expect(bg, dark ? const Color(0xFF6E6862) : const Color(0xFF928C86));
        }
      }
    }
  });

  testWidgets('EDGE — disabled + isLoading keeps ACTIVE fill', (t) async {
    await t.pumpWidget(host(
      const AppButton(label: 'X', onPressed: null, disabled: true, isLoading: true),
      dark: false,
    ));
    final bg = styleOf(t).backgroundColor!.resolve({WidgetState.disabled});
    final scheme = Theme.of(t.element(find.byType(ElevatedButton))).colorScheme;
    // ignore: avoid_print
    print('EDGE disabled+loading | bg=${hx(bg)} primary=${hx(scheme.primary)} '
        'spinners=${find.byType(CircularProgressIndicator).evaluate().length}');
    expect(bg, scheme.primary);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('ERROR PATH — callback must not fire while disabled/loading', (t) async {
    var fired = 0;
    for (final cfg in [
      [true, false],
      [false, true],
      [true, true],
    ]) {
      await t.pumpWidget(host(
        AppButton(label: 'Tap', onPressed: () => fired++, disabled: cfg[0], isLoading: cfg[1]),
        dark: false,
      ));
      await t.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 300));
    }
    await t.pumpWidget(host(AppButton(label: 'Tap', onPressed: () => fired++), dark: false));
    await t.tap(find.byType(ElevatedButton));
    await t.pump(const Duration(milliseconds: 300));
    // ignore: avoid_print
    print('ERROR PATH | fired=$fired (expected exactly 1 = enabled control)');
    expect(fired, 1);
  });

  testWidgets('EDGE — focus border does not shift layout', (t) async {
    for (final v in [AppButtonVariant.text, AppButtonVariant.outline]) {
      await t.pumpWidget(host(AppButton(label: 'Focar', onPressed: () {}, variant: v), dark: false));
      await t.pump(const Duration(milliseconds: 400));
      final r1 = t.getRect(find.byType(ElevatedButton));
      FocusScope.of(t.element(find.byType(ElevatedButton))).nextFocus();
      await t.pump(const Duration(milliseconds: 400));
      final r2 = t.getRect(find.byType(ElevatedButton));
      // ignore: avoid_print
      print('LAYOUT | ${v.name} | idle=$r1 focused=$r2 shift=${r1 == r2 ? "none" : "SHIFTED"}');
      expect(r1, r2);
    }
  });
}
