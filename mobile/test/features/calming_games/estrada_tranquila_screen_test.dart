import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/calming_games/calming_session_summary.dart';
import 'package:sincro_mobile/features/calming_games/estrada_tranquila_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: sincroLightTheme,
        home: const EstradaTranquilaScreen(seed: 1),
      ),
    );
    await tester.pump();
  }

  /// Avança o relógio de teste em pequenos incrementos (como faria um
  /// dispositivo real a ~60fps), já que um único `pump(duration)` só produz
  /// um frame — e o modelo puro limita `dt` a 0.1s por frame de propósito.
  Future<void> pumpFrames(WidgetTester tester, Duration total) async {
    const Duration step = Duration(milliseconds: 16);
    Duration remaining = total;
    while (remaining > Duration.zero) {
      final Duration thisStep = remaining < step ? remaining : step;
      await tester.pump(thisStep);
      remaining -= thisStep;
    }
  }

  testWidgets('renders and advances the model over 3 seconds', (tester) async {
    await pumpScreen(tester);

    final EstradaTranquilaScreenState state = tester.state(
      find.byType(EstradaTranquilaScreen),
    );
    expect(state.debugModel.elapsed, 0);

    await pumpFrames(tester, const Duration(seconds: 3));

    expect(state.debugModel.elapsed, greaterThan(2.5));
    expect(find.text('Estrada Tranquila'), findsOneWidget);
  });

  testWidgets('horizontal drag changes the model lateral position', (tester) async {
    await pumpScreen(tester);

    final EstradaTranquilaScreenState state = tester.state(
      find.byType(EstradaTranquilaScreen),
    );
    expect(state.debugModel.lateral, 0.0);

    final TestGesture gesture = await tester.startGesture(const Offset(350, 700));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-300, 0));
    await pumpFrames(tester, const Duration(milliseconds: 500));

    expect(state.debugModel.touchTarget, isNotNull);
    expect(state.debugModel.lateral, lessThan(0.0));

    await gesture.up();
    await pumpFrames(tester, const Duration(milliseconds: 16));
    expect(state.debugModel.touchTarget, isNull);
  });

  testWidgets('tapping Encerrar shows the calming session summary', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Encerrar'));
    await tester.pumpAndSettle();

    expect(find.byType(CalmingSessionSummary), findsOneWidget);
  });
}
