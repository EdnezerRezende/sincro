import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/core/theme.dart';
import '../../lib/core/widgets/app_button.dart';

const String outDir =
    '/private/tmp/claude-501/-Users-ed-Desenvolvimento-projetos-sincro/9c595fdb-092a-49b5-bffd-51ad092779ba/scratchpad';

double _chan(int c) {
  final v = c / 255.0;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double lum(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return 0.2126 * _chan(r) + 0.7152 * _chan(g) + 0.0722 * _chan(b);
}

String hex(Color c) {
  final a = (c.a * 255).round();
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return '#${a.toRadixString(16).padLeft(2, '0')}'
          '${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

ButtonStyle styleOf(WidgetTester tester) {
  final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
  return btn.style!;
}

Future<void> pump(WidgetTester tester, ThemeData theme, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: child)),
  ));
  await tester.pumpAndSettle();
}

Future<void> dump(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first);
  final ui.Image img = await boundary.toImage(pixelRatio: 3.0);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('A/B: disabled outline foreground, light + dark', (tester) async {
    for (final entry in {
      'light': sincroLightTheme,
      'dark': sincroDarkTheme
    }.entries) {
      await pump(
        tester,
        entry.value,
        const AppButton(
          label: 'Outline',
          onPressed: null,
          variant: AppButtonVariant.outline,
        ),
      );
      final s = styleOf(tester);
      final fg = s.foregroundColor!.resolve({WidgetState.disabled})!;
      final bg = s.backgroundColor!.resolve({WidgetState.disabled})!;
      print('[OUTLINE-DISABLED ${entry.key}] fg=${hex(fg)} L=${lum(fg).toStringAsFixed(6)} '
          'bg=${hex(bg)}');
    }
  });

  testWidgets('primary disabled fill unchanged', (tester) async {
    for (final entry in {
      'light': sincroLightTheme,
      'dark': sincroDarkTheme
    }.entries) {
      await pump(
        tester,
        entry.value,
        const AppButton(
            label: 'Primary',
            onPressed: null,
            variant: AppButtonVariant.primary),
      );
      final s = styleOf(tester);
      final bg = s.backgroundColor!.resolve({WidgetState.disabled})!;
      final fg = s.foregroundColor!.resolve({WidgetState.disabled})!;
      print('[PRIMARY-DISABLED ${entry.key}] bg=${hex(bg)} fg=${hex(fg)}');
    }
  });

  testWidgets('focused overlay + focused shape per variant', (tester) async {
    for (final entry in {
      'light': sincroLightTheme,
      'dark': sincroDarkTheme
    }.entries) {
      for (final v in AppButtonVariant.values) {
        await pump(
          tester,
          entry.value,
          AppButton(label: 'X', onPressed: () {}, variant: v),
        );
        final s = styleOf(tester);
        final ovFocus = s.overlayColor!.resolve({WidgetState.focused});
        final ovIdle = s.overlayColor!.resolve(<WidgetState>{});
        final shFocus =
            s.shape!.resolve({WidgetState.focused}) as RoundedRectangleBorder;
        final shIdle =
            s.shape!.resolve(<WidgetState>{}) as RoundedRectangleBorder;
        print('[FOCUS ${entry.key}/${v.name}] '
            'overlayFocused=${ovFocus == null ? "NULL" : hex(ovFocus)} alpha=${ovFocus?.a.toStringAsFixed(3)} '
            'overlayIdle=${ovIdle == null ? "NULL" : hex(ovIdle)} '
            'sideFocused=${hex(shFocus.side.color)}/${shFocus.side.width} '
            'sideIdle=${hex(shIdle.side.color)}/${shIdle.side.width}');
      }
    }
  });

  testWidgets('REAL focus traversal changes rendered pixels (outline)',
      (tester) async {
    for (final entry in {
      'light': sincroLightTheme,
      'dark': sincroDarkTheme
    }.entries) {
      await tester.pumpWidget(MaterialApp(
        theme: entry.value,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppButton(
                    label: 'Tab',
                    onPressed: () {},
                    variant: AppButtonVariant.outline),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await dump(tester, 'outline_${entry.key}_idle');

      // Real keyboard traversal
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final btnState = tester.state(find.byType(ElevatedButton));
      // ignore: avoid_dynamic_calls
      final focusNode = Focus.of(tester.element(find.byType(ElevatedButton)));
      print('[TRAVERSAL ${entry.key}] hasFocus=${focusNode.hasFocus} '
          'primaryFocus=${FocusManager.instance.primaryFocus?.debugLabel} '
          'state=$btnState');
      await dump(tester, 'outline_${entry.key}_focused');

      final a = File('$outDir/outline_${entry.key}_idle.png').readAsBytesSync();
      final b =
          File('$outDir/outline_${entry.key}_focused.png').readAsBytesSync();
      final identical =
          a.length == b.length && List.generate(a.length, (i) => a[i] == b[i]).every((e) => e);
      print('[TRAVERSAL ${entry.key}] idle vs focused bytes identical = $identical');
    }
  });

  testWidgets('gallery capture: all variants x states x themes',
      (tester) async {
    for (final entry in {
      'light': sincroLightTheme,
      'dark': sincroDarkTheme
    }.entries) {
      await tester.binding.setSurfaceSize(const Size(430, 700));
      await tester.pumpWidget(MaterialApp(
        theme: entry.value,
        home: Scaffold(
          body: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('enabled'),
                  const SizedBox(height: 8),
                  Row(children: [
                    AppButton(label: 'Primary', onPressed: () {}),
                    const SizedBox(width: 8),
                    AppButton(
                        label: 'Outline',
                        onPressed: () {},
                        variant: AppButtonVariant.outline),
                    const SizedBox(width: 8),
                    AppButton(
                        label: 'Text',
                        onPressed: () {},
                        variant: AppButtonVariant.text),
                  ]),
                  const SizedBox(height: 20),
                  const Text('disabled'),
                  const SizedBox(height: 8),
                  const Row(children: [
                    AppButton(label: 'Primary', onPressed: null),
                    SizedBox(width: 8),
                    AppButton(
                        label: 'Outline',
                        onPressed: null,
                        variant: AppButtonVariant.outline),
                    SizedBox(width: 8),
                    AppButton(
                        label: 'Text',
                        onPressed: null,
                        variant: AppButtonVariant.text),
                  ]),
                  const SizedBox(height: 20),
                  const Text('loading'),
                  const SizedBox(height: 8),
                  Row(children: [
                    AppButton(
                        label: 'Primary', onPressed: () {}, isLoading: true),
                    const SizedBox(width: 8),
                    AppButton(
                        label: 'Outline',
                        onPressed: () {},
                        isLoading: true,
                        variant: AppButtonVariant.outline),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await dump(tester, 'gallery_${entry.key}');
      await tester.binding.setSurfaceSize(null);
    }
  });
}
