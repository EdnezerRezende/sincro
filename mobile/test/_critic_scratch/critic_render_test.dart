import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/core/theme.dart';
import '../../lib/core/widgets/app_button.dart';

const String outDir =
    '/private/tmp/claude-501/-Users-ed-Desenvolvimento-projetos-sincro/9c595fdb-092a-49b5-bffd-51ad092779ba/scratchpad';

Future<void> loadRealFont() async {
  final loader = FontLoader('Atkinson Hyperlegible');
  for (final f in [
    'assets/fonts/AtkinsonHyperlegible-Regular.ttf',
    'assets/fonts/AtkinsonHyperlegible-Bold.ttf',
  ]) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

class Shot {
  final Uint8List rgba;
  final int w;
  final int h;
  Shot(this.rgba, this.w, this.h);
}

Future<Shot> shoot(WidgetTester tester, String? saveAs,
    {double pixelRatio = 3.0}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('cap')));
  late Shot result;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    result = Shot(raw!.buffer.asUint8List(), image.width, image.height);
    if (saveAs != null) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$outDir/$saveAs.png')
          .writeAsBytesSync(png!.buffer.asUint8List(), flush: true);
    }
  });
  return result;
}

String diff(Shot a, Shot b) {
  if (a.w != b.w || a.h != b.h) return 'SIZE MISMATCH';
  int differing = 0;
  int maxDelta = 0;
  for (int i = 0; i < a.rgba.length; i += 4) {
    int d = 0;
    for (int c = 0; c < 3; c++) {
      final delta = (a.rgba[i + c] - b.rgba[i + c]).abs();
      if (delta > d) d = delta;
    }
    if (d > 0) differing++;
    if (d > maxDelta) maxDelta = d;
  }
  final total = a.rgba.length ~/ 4;
  final pct = (100.0 * differing / total);
  return 'pixelsChanged=${pct.toStringAsFixed(2)}% maxChannelDelta=$maxDelta '
      '(identical=${differing == 0})';
}

Widget harness(ThemeData theme, Widget child) => MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey('cap'),
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRealFont();
  });

  testWidgets('FOCUS VISIBILITY: real Tab traversal, idle vs focused pixels',
      (tester) async {
    for (final t in {'light': sincroLightTheme, 'dark': sincroDarkTheme}
        .entries) {
      for (final v in AppButtonVariant.values) {
        await tester.pumpWidget(harness(
          t.value,
          AppButton(label: 'Focar', onPressed: () {}, variant: v),
        ));
        await tester.pumpAndSettle();
        final idle = await shoot(tester, 'focus_${t.key}_${v.name}_idle');

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();

        final pf = FocusManager.instance.primaryFocus;
        final btnCtx = tester.element(find.byType(ElevatedButton));
        final onBtn = pf != null &&
            pf.context != null &&
            (pf.context == btnCtx ||
                find
                    .descendant(
                        of: find.byType(ElevatedButton),
                        matching: find.byWidget(pf.context!.widget))
                    .evaluate()
                    .isNotEmpty);

        final focused = await shoot(tester, 'focus_${t.key}_${v.name}_focused');
        print('[FOCUS ${t.key}/${v.name}] tabReachedButton=$onBtn '
            'primaryFocusOwner=${pf?.context?.widget.runtimeType} :: ${diff(idle, focused)}');
      }
    }
  });

  testWidgets('GALLERY: all variants x states, 390dp + 1440dp, both themes',
      (tester) async {
    Widget row(String title, List<Widget> kids) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 10, runSpacing: 10, children: kids),
            const SizedBox(height: 18),
          ],
        );

    for (final w in [390.0, 1440.0]) {
      for (final t in {'light': sincroLightTheme, 'dark': sincroDarkTheme}
          .entries) {
        await tester.binding.setSurfaceSize(Size(w, 760));
        await tester.pumpWidget(MaterialApp(
          theme: t.value,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: const ValueKey('cap'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      row('ENABLED', [
                        AppButton(label: 'Primary', onPressed: () {}),
                        AppButton(
                            label: 'Secondary',
                            onPressed: () {},
                            variant: AppButtonVariant.secondary),
                        AppButton(
                            label: 'Outline',
                            onPressed: () {},
                            variant: AppButtonVariant.outline),
                        AppButton(
                            label: 'Text',
                            onPressed: () {},
                            variant: AppButtonVariant.text),
                      ]),
                      row('DISABLED', const [
                        AppButton(label: 'Primary', onPressed: null),
                        AppButton(
                            label: 'Secondary',
                            onPressed: null,
                            variant: AppButtonVariant.secondary),
                        AppButton(
                            label: 'Outline',
                            onPressed: null,
                            variant: AppButtonVariant.outline),
                        AppButton(
                            label: 'Text',
                            onPressed: null,
                            variant: AppButtonVariant.text),
                      ]),
                      row('LOADING', [
                        AppButton(
                            label: 'Primary',
                            onPressed: () {},
                            isLoading: true),
                        AppButton(
                            label: 'Outline',
                            onPressed: () {},
                            isLoading: true,
                            variant: AppButtonVariant.outline),
                      ]),
                      row('SIZES', [
                        AppButton(
                            label: 'small',
                            onPressed: () {},
                            size: AppButtonSize.small,
                            variant: AppButtonVariant.outline),
                        AppButton(
                            label: 'medium',
                            onPressed: () {},
                            size: AppButtonSize.medium,
                            variant: AppButtonVariant.outline),
                        AppButton(
                            label: 'large',
                            onPressed: () {},
                            size: AppButtonSize.large,
                            variant: AppButtonVariant.outline),
                      ]),
                      row('ICON', [
                        AppButton(
                            label: 'Guardar',
                            icon: Icons.check,
                            onPressed: () {}),
                        AppButton(
                            label: 'Seguinte',
                            icon: Icons.arrow_forward,
                            iconAfterLabel: true,
                            onPressed: () {},
                            variant: AppButtonVariant.outline),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 120));
        await shoot(tester, 'gallery_${w.toInt()}_${t.key}', pixelRatio: 2.0);
        print('[GALLERY] ${w.toInt()}dp ${t.key} captured');
        await tester.binding.setSurfaceSize(null);
      }
    }
  });

  testWidgets('FOCUS side-by-side capture: outline + text, focused',
      (tester) async {
    for (final t in {'light': sincroLightTheme, 'dark': sincroDarkTheme}
        .entries) {
      final n1 = FocusNode(debugLabel: 'outline');
      final n2 = FocusNode(debugLabel: 'text');
      final n3 = FocusNode(debugLabel: 'primary');
      await tester.pumpWidget(MaterialApp(
        theme: t.value,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('cap'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Focus(
                      focusNode: n3,
                      child: AppButton(label: 'Primary', onPressed: () {})),
                  const SizedBox(width: 14),
                  Focus(
                      focusNode: n1,
                      child: AppButton(
                          label: 'Outline',
                          onPressed: () {},
                          variant: AppButtonVariant.outline)),
                  const SizedBox(width: 14),
                  Focus(
                      focusNode: n2,
                      child: AppButton(
                          label: 'Text',
                          onPressed: () {},
                          variant: AppButtonVariant.text)),
                ]),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await shoot(tester, 'trio_${t.key}_idle', pixelRatio: 4.0);
      print('[TRIO ${t.key}] idle captured');
    }
  });
}
