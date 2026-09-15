import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/calming_games/calming_session_summary.dart';
import 'package:sincro_mobile/features/calming_games/voo_sereno_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: sincroLightTheme,
        home: const VooSerenoScreen(seed: 1),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders and advances the model over 3 seconds', (tester) async {
    await pumpScreen(tester);

    final VooSerenoScreenState state = tester.state(find.byType(VooSerenoScreen));
    expect(state.debugModel.elapsed, 0);

    // `model.update` clamps each step to 0.1s (to avoid jumps after a
    // background pause), so we advance in small steps that add up to ~3s
    // instead of a few large `pump`s that would each be clamped away.
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(state.debugModel.elapsed, greaterThan(2.5));
    expect(find.textContaining('Voo Sereno'), findsOneWidget);
  });

  testWidgets('vertical drag changes the model altitude', (tester) async {
    await pumpScreen(tester);

    final VooSerenoScreenState state = tester.state(find.byType(VooSerenoScreen));
    final double initialAltitude = state.debugModel.altitude;

    // Hold the drag (don't release) so `touchTarget` stays set while we
    // observe the spring pulling the plane toward it; releasing would call
    // `releaseTouch()` by design (spec: letting go is never an error).
    final TestGesture gesture = await tester.startGesture(const Offset(200, 700));
    await gesture.moveBy(const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(state.debugModel.touchTarget, isNotNull);

    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(state.debugModel.altitude, isNot(equals(initialAltitude)));

    await gesture.up();
  });

  testWidgets('tapping Encerrar shows the calming session summary with chips', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Encerrar'));
    await tester.pumpAndSettle();

    expect(find.byType(CalmingSessionSummary), findsOneWidget);
    expect(find.text('Mais calmo(a)'), findsOneWidget);
    expect(find.text('Igual'), findsOneWidget);
    expect(find.text('Ainda agitado(a)'), findsOneWidget);
  });

  group('CalmingSessionSummary time label', () {
    testWidgets('pluralizes minutes correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: CalmingSessionSummary(
            elapsed: const Duration(seconds: 30),
            onClose: () {},
          ),
        ),
      );
      expect(find.text('Você ficou menos de um minuto aqui.'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: CalmingSessionSummary(
            elapsed: const Duration(minutes: 1),
            onClose: () {},
          ),
        ),
      );
      expect(find.text('Você ficou 1 minuto aqui.'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: CalmingSessionSummary(
            elapsed: const Duration(minutes: 3),
            onClose: () {},
          ),
        ),
      );
      expect(find.text('Você ficou 3 minutos aqui.'), findsOneWidget);
    });

    testWidgets('selecting a chip shows a kind response', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: CalmingSessionSummary(
            elapsed: const Duration(minutes: 2),
            onClose: () {},
          ),
        ),
      );

      await tester.tap(find.text('Mais calmo(a)'));
      await tester.pumpAndSettle();

      expect(find.text('Que bom. Volte quando quiser.'), findsOneWidget);
    });
  });
}
