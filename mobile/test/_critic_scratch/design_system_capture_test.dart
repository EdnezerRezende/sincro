// GAUNTLET CRITIC SCRATCH HARNESS - not part of the product. Delete after the run.
// Captures Design System (theme.dart) + base components (AppButton, AppCard,
// AppInput, AppChip, AppDialog) as real PNGs via flutter_test's built-in
// matchesGoldenFile (ships with the SDK, already a dev_dependency — no new
// package, no simulator/emulator). Also checks WCAG AA contrast on the actual
// theme colors and reads border widths off the real widget tree.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/core/widgets/app_button.dart';
import 'package:sincro_mobile/core/widgets/app_card.dart';
import 'package:sincro_mobile/core/widgets/app_chip.dart';
import 'package:sincro_mobile/core/widgets/app_dialog.dart';
import 'package:sincro_mobile/core/widgets/app_input.dart';

// PNGs land in the scratchpad, never in the repo — matches this project's
// "not part of the product" convention for critic scratch harnesses.
const outDir =
    '/private/tmp/claude-501/-Users-ed-Desenvolvimento-projetos-sincro/9c595fdb-092a-49b5-bffd-51ad092779ba/scratchpad/shots';

double _lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double contrast(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

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

Future<void> shoot(WidgetTester tester, String name, Widget child, ThemeData theme,
    {Size size = const Size(390, 200)}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: Center(child: child)),
  ));
  await tester.pump(const Duration(milliseconds: 300)); // fixed pump: covers finite
  // animations (dialog fade/scale) without waiting on an infinite one (spinner)
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$outDir/$name.png')));
}

void main() {
  setUpAll(loadRealFonts);

  // ---- 1) WCAG AA contrast on the real theme.dart colors -------------------
  group('WCAG AA contrast (computed from real theme.dart colors)', () {
    final light = sincroLightTheme.colorScheme;
    final dark = sincroDarkTheme.colorScheme;
    final pairs = <String, List<Color>>{
      'light primary/surface': [light.primary, light.surface],
      'light onPrimary/primary': [light.onPrimary, light.primary],
      'light secondary/surface': [light.secondary, light.surface],
      'light error/surface': [light.error, light.surface],
      'light onSurface/surface': [light.onSurface, light.surface],
      'light onSurfaceVariant/surface': [light.onSurfaceVariant, light.surface],
      'dark primary/surface': [dark.primary, dark.surface],
      'dark onPrimary/primary': [dark.onPrimary, dark.primary],
      'dark onSurface/surface': [dark.onSurface, dark.surface],
      'dark error/surface': [dark.error, dark.surface],
    };
    for (final e in pairs.entries) {
      test(e.key, () {
        final ratio = contrast(e.value[0], e.value[1]);
        // ignore: avoid_print
        print('${e.key}: ${ratio.toStringAsFixed(2)}:1');
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '${e.key} = ${ratio.toStringAsFixed(2)}:1');
      });
    }
  });

  // ---- 2) Border widths read off the real widget tree -----------------------
  group('Border widths (inspected on real widget tree)', () {
    testWidgets('AppCard flat: 1.0dp normal / 2.0dp selected', (tester) async {
      await tester.pumpWidget(
          MaterialApp(theme: sincroLightTheme, home: Scaffold(body: AppCard(title: 'x', variant: AppCardVariant.flat))));
      final m1 = tester.widget<Material>(
          find.byWidgetPredicate((w) => w is Material && w.shape is RoundedRectangleBorder && w.color != null));
      expect((m1.shape as RoundedRectangleBorder).side.width, 1.0);

      await tester.pumpWidget(MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(body: AppCard(title: 'x', variant: AppCardVariant.flat, selected: true))));
      final m2 = tester.widget<Material>(
          find.byWidgetPredicate((w) => w is Material && w.shape is RoundedRectangleBorder && w.color != null));
      expect((m2.shape as RoundedRectangleBorder).side.width, 2.0);
    });

    testWidgets('AppInput: 1.5dp default / 2.0dp focused+error', (tester) async {
      await tester.pumpWidget(
          MaterialApp(theme: sincroLightTheme, home: const Scaffold(body: AppInput(label: 'Email'))));
      final deco = tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
      expect((deco.enabledBorder as OutlineInputBorder).borderSide.width, 1.5);
      expect((deco.focusedBorder as OutlineInputBorder).borderSide.width, 2.0);
      expect((deco.errorBorder as OutlineInputBorder).borderSide.width, 2.0);
    });
  });

  // ---- 3) Screenshots — every component, key states, light+dark -------------
  testWidgets('AppButton — variants x states x themes', (tester) async {
    await shoot(tester, 'button_disabled_light', const AppButton(label: 'Salvar', onPressed: null), sincroLightTheme);
    await shoot(tester, 'button_primary_light', AppButton(label: 'Salvar', onPressed: () {}), sincroLightTheme);
    await shoot(tester, 'button_loading_light', AppButton(label: 'Salvar', onPressed: () {}, isLoading: true),
        sincroLightTheme);
    await shoot(tester, 'button_outline_dark',
        AppButton(label: 'Cancelar', onPressed: () {}, variant: AppButtonVariant.outline), sincroDarkTheme);
  });

  testWidgets('AppCard — variants x states x themes', (tester) async {
    await shoot(tester, 'card_elevated_light',
        AppCard(title: 'Conta de luz', subtitle: 'Vence em 5 dias', icon: Icons.bolt), sincroLightTheme,
        size: const Size(390, 180));
    await shoot(tester, 'card_flat_selected_dark',
        AppCard(title: 'Selecionado', variant: AppCardVariant.flat, selected: true), sincroDarkTheme,
        size: const Size(390, 180));
    await shoot(tester, 'card_disabled_light', AppCard(title: 'Desabilitado', enabled: false), sincroLightTheme,
        size: const Size(390, 180));
  });

  testWidgets('AppInput — states x themes (light)', (tester) async {
    await shoot(tester, 'input_default_light', const AppInput(label: 'Email', placeholder: 'seu@email.com'),
        sincroLightTheme, size: const Size(390, 120));
    await shoot(tester, 'input_error_light', const AppInput(label: 'Senha', error: 'Senha muito curta'),
        sincroLightTheme, size: const Size(390, 140));
    await shoot(tester, 'input_disabled_light', const AppInput(label: 'Email', enabled: false),
        sincroLightTheme, size: const Size(390, 120));
  });

  // Dark shots isolated — avoids InputDecorator border-color animation bleed
  // that occurs when light → dark theme swap happens within the same testWidgets.
  testWidgets('AppInput — states x themes (dark)', (tester) async {
    await shoot(tester, 'input_disabled_dark', const AppInput(label: 'Email', enabled: false), sincroDarkTheme,
        size: const Size(390, 120));
  });

  testWidgets('AppChip — variants x states x themes', (tester) async {
    await shoot(tester, 'chip_default_light', AppChip(label: 'Filtro'), sincroLightTheme, size: const Size(200, 100));
    await shoot(tester, 'chip_selected_dark', AppChip(label: 'Selecionado', selected: true), sincroDarkTheme,
        size: const Size(200, 100));
    await shoot(tester, 'chip_disabled_light', AppChip(label: 'Desabilitado', enabled: false), sincroLightTheme,
        size: const Size(200, 100));
  });

  testWidgets('AppDialog — light', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 500));
    await tester.pumpWidget(MaterialApp(
      theme: sincroLightTheme,
      home: Scaffold(
        body: Center(
          child: AppDialog(
            title: 'Confirmar ação',
            content: 'Tem certeza que deseja continuar?',
            actions: [
              DialogAction(label: 'Cancelar', onPressed: () {}, type: 'secondary'),
              DialogAction(label: 'Confirmar', onPressed: () {}, type: 'primary'),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$outDir/dialog_light.png')));
  });

  // ---- 4) Pressed state — closest device-accurate equivalent to hover -------
  //         (hover doesn't exist on touch); real gesture held down.
  testWidgets('AppButton — pressed state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 120));
    await tester.pumpWidget(MaterialApp(
      theme: sincroLightTheme,
      home: Scaffold(body: Center(child: AppButton(label: 'Pressione', onPressed: () {}))),
    ));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(ElevatedButton)));
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$outDir/button_pressed_light.png')));
    await gesture.up();
    await tester.pump();
  });
}
