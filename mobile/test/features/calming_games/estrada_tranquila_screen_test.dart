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
    expect(find.text('Continuar'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
    expect(find.text('Voltar'), findsNothing);
  });

  testWidgets('Continuar resumes the game where it stopped', (tester) async {
    await pumpScreen(tester);
    await pumpFrames(tester, const Duration(seconds: 2));
    final EstradaTranquilaScreenState state = tester.state(find.byType(EstradaTranquilaScreen));
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
    final EstradaTranquilaScreenState state = tester.state(find.byType(EstradaTranquilaScreen));

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
                  MaterialPageRoute<void>(builder: (_) => const EstradaTranquilaScreen(seed: 1)),
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
    expect(find.byType(EstradaTranquilaScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Encerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair'));
    await pumpFrames(tester, const Duration(milliseconds: 600));

    expect(find.byType(EstradaTranquilaScreen), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
  });
}
