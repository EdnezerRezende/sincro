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
    expect(find.text('Continuar'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
    expect(find.text('Voltar'), findsNothing);
  });

  testWidgets('Continuar resumes the game where it stopped', (tester) async {
    await pumpScreen(tester);
    await pumpFrames(tester, const Duration(seconds: 2));
    final VooSerenoScreenState state = tester.state(find.byType(VooSerenoScreen));
    final double before = state.debugModel.elapsed;

    await tester.tap(find.byTooltip('Encerrar'));
    await tester.pumpAndSettle();
    await pumpFrames(tester, const Duration(seconds: 1));
    expect(state.debugModel.elapsed, closeTo(before, 0.05), reason: 'jogo pausado no resumo');

    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.byType(CalmingSessionSummary), findsNothing);
    await pumpFrames(tester, const Duration(seconds: 1));
    expect(state.debugModel.elapsed, greaterThan(before + 0.5), reason: 'jogo retomado');
  });

  testWidgets('backgrounding and returning does not resume behind the summary', (tester) async {
    await pumpScreen(tester);
    await pumpFrames(tester, const Duration(seconds: 1));
    final VooSerenoScreenState state = tester.state(find.byType(VooSerenoScreen));

    await tester.tap(find.byTooltip('Encerrar'));
    await tester.pumpAndSettle();
    final double paused = state.debugModel.elapsed;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpFrames(tester, const Duration(seconds: 1));

    expect(find.byType(CalmingSessionSummary), findsOneWidget);
    expect(state.debugModel.elapsed, closeTo(paused, 0.05), reason: 'não retoma por trás do resumo');

    await tester.tap(find.text('Continuar'));
    await pumpFrames(tester, const Duration(seconds: 1));
    expect(state.debugModel.elapsed, greaterThan(paused + 0.5));
  });

  testWidgets('Sair leaves the game screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: sincroLightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const VooSerenoScreen(seed: 1)),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await pumpFrames(tester, const Duration(milliseconds: 600));
    expect(find.byType(VooSerenoScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Encerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair'));
    await pumpFrames(tester, const Duration(milliseconds: 600));

    expect(find.byType(VooSerenoScreen), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
  });

  group('CalmingSessionSummary time label', () {
    testWidgets('pluralizes minutes correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: CalmingSessionSummary(
            elapsed: const Duration(seconds: 30),
            onContinue: () {},
            onExit: () {},
          ),
        ),
      );
      expect(find.text('Você ficou menos de um minuto aqui.'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: CalmingSessionSummary(
            elapsed: const Duration(minutes: 1),
            onContinue: () {},
            onExit: () {},
          ),
        ),
      );
      expect(find.text('Você ficou 1 minuto aqui.'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: CalmingSessionSummary(
            elapsed: const Duration(minutes: 3),
            onContinue: () {},
            onExit: () {},
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
            onContinue: () {},
            onExit: () {},
          ),
        ),
      );

      await tester.tap(find.text('Mais calmo(a)'));
      await tester.pumpAndSettle();

      expect(find.text('Que bom. Volte quando quiser.'), findsOneWidget);
    });
  });
}
