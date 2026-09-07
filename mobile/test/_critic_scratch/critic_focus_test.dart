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
  final int w, h;
  Shot(this.rgba, this.w, this.h);
}

Future<Shot> shoot(WidgetTester tester, String? saveAs, {double pr = 4.0}) async {
  final b = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('cap')));
  late Shot r;
  await tester.runAsync(() async {
    final img = await b.toImage(pixelRatio: pr);
    final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    r = Shot(raw!.buffer.asUint8List(), img.width, img.height);
    if (saveAs != null) {
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$outDir/$saveAs.png').writeAsBytesSync(png!.buffer.asUint8List(), flush: true);
    }
  });
  return r;
}

String diff(Shot a, Shot b) {
  if (a.w != b.w || a.h != b.h) return 'SIZE MISMATCH';
  int differing = 0, maxDelta = 0;
  for (int i = 0; i < a.rgba.length; i += 4) {
    int d = 0;
    for (int c = 0; c < 3; c++) {
      final delta = (a.rgba[i + c] - b.rgba[i + c]).abs();
      if (delta > d) d = delta;
    }
    if (d > 0) differing++;
    if (d > maxDelta) maxDelta = d;
  }
  final pct = 100.0 * differing / (a.rgba.length ~/ 4);
  return 'pixelsChanged=${pct.toStringAsFixed(2)}% maxChannelDelta=$maxDelta identical=${differing == 0}';
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRealFont();
  });

  for (final tEntry in {'light': sincroLightTheme, 'dark': sincroDarkTheme}.entries) {
    for (final v in AppButtonVariant.values) {
      testWidgets('TAB FOCUS ${tEntry.key}/${v.name}', (tester) async {
        final node = FocusNode(debugLabel: 'probe');
        addTearDown(node.dispose);
        await tester.pumpWidget(MaterialApp(
          theme: tEntry.value,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // A focus sink placed BEFORE the button in traversal order.
                Focus(focusNode: node, child: const SizedBox(width: 1, height: 1)),
                const SizedBox(height: 30),
                RepaintBoundary(
                  key: const ValueKey('cap'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AppButton(
                        label: 'Focar', onPressed: () {}, variant: v),
                  ),
                ),
              ]),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // Park focus on the sink -> button is definitely NOT focused.
        node.requestFocus();
        await tester.pumpAndSettle();
        final btnFocusBefore = Focus.of(
                tester.element(find.byType(ElevatedButton)),
                scopeOk: true)
            .hasFocus;
        final idle = await shoot(tester, 'tab_${tEntry.key}_${v.name}_idle');

        // Real keyboard traversal.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();

        final pf = FocusManager.instance.primaryFocus;
        final reached = find
            .descendant(
                of: find.byType(ElevatedButton),
                matching: find.byWidgetPredicate((w) => w is Focus && w.focusNode == pf))
            .evaluate()
            .isNotEmpty ||
            (pf?.context != null &&
                find
                    .descendant(
                        of: find.byType(ElevatedButton),
                        matching: find.byElementPredicate((e) => e == pf!.context))
                    .evaluate()
                    .isNotEmpty);

        final focused = await shoot(tester, 'tab_${tEntry.key}_${v.name}_focused');
        print('RESULT ${tEntry.key}/${v.name} :: focusedBeforeTab=$btnFocusBefore '
            'tabLandedOnButton=$reached label=${pf?.debugLabel} :: ${diff(idle, focused)}');
      });
    }
  }
}
