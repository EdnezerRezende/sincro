import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_alert_service.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_cache.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_health_service.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_providers.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_screen.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';
import 'package:sincro_mobile/features/biofeedback/linha_de_base.dart';
import 'package:sincro_mobile/features/biofeedback/serie_dia.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_stress_detector.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary_calculator.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_sync_service.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_cards_repository.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/sensory_profile_repository.dart';

class _ThrowingSyncService extends BiofeedbackSyncService {
  _ThrowingSyncService()
    : super(
        BiofeedbackHealthService(),
        BiofeedbackCache(),
        BiofeedbackSummaryCalculator(),
        BiofeedbackStressDetector(),
        BiofeedbackAlertService(FlutterLocalNotificationsPlugin()),
        SensoryProfileRepository(Dio()),
        GroundingCardsRepository(Dio()),
      );

  @override
  Future<void> sincronizar({DateTime? agora}) {
    throw Exception('falha de sincronização simulada');
  }
}

Widget _app({
  required bool? permissao,
  BiofeedbackSummary? resumo,
  SerieDia? serie,
  int diasNoHistorico = 0,
  ThemeData? theme,
  double textScale = 1.0,
}) {
  return ProviderScope(
    overrides: [
      biofeedbackResumoProvider.overrideWith((ref) async => resumo),
      biofeedbackSerieDiaProvider.overrideWith((ref) async => serie),
      biofeedbackDiasNoHistoricoProvider.overrideWith((ref) async => diasNoHistorico),
      biofeedbackPermissaoProvider.overrideWith((ref) async => permissao),
      biofeedbackSyncServiceProvider.overrideWithValue(_ThrowingSyncService()),
    ],
    child: MaterialApp(
      theme: theme ?? sincroLightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const BiofeedbackScreen(),
    ),
  );
}

void main() {
  testWidgets('shows the generic empty message when permission status is unknown (null)', (
    tester,
  ) async {
    await tester.pumpWidget(_app(permissao: null));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nenhum dado ainda'), findsOneWidget);
    expect(find.text('Conceder acesso'), findsNothing);
  });

  testWidgets('shows a permission-specific message and a grant button when denied (false)', (
    tester,
  ) async {
    await tester.pumpWidget(_app(permissao: false));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sem acesso aos dados de saúde'), findsOneWidget);
    expect(find.text('Conceder acesso'), findsOneWidget);
  });

  testWidgets('shows a calm error message when pull-to-refresh sync fails', (tester) async {
    await tester.pumpWidget(_app(permissao: true));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.textContaining('Não foi possível sincronizar agora'), findsOneWidget);
  });

  // Prancha "Biofeedback" da direção A com dados reais: dois tiles + painel de estado. Antes, a
  // Row com `stretch` dentro da ListView recebia altura infinita e a tela abria em branco — e
  // nenhum teste montava a tela com resumo não nulo.
  for (final theme in [sincroLightTheme, sincroDarkTheme]) {
    testWidgets('renders the stat tiles and state panel with a real summary (${theme.brightness.name})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        permissao: true,
        theme: theme,
        resumo: BiofeedbackSummary(
          ultimaFc: 70,
          mediaFcHoje: 68,
          mediaVfcHoje: 54,
          estadoEstresse: EstadoEstresse.calmo,
          atualizadoEm: DateTime.now(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Última leitura'), findsOneWidget);
      expect(find.text('Em repouso'), findsOneWidget);
      expect(find.text('Mínima · Máxima'), findsOneWidget);
      expect(find.text('Variabilidade'), findsOneWidget);
      // Sem FC em repouso nativa, o tile "Em repouso" mostra a média filtrada de hoje.
      expect(find.text('média de hoje'), findsOneWidget);
      expect(find.text('Estado atual: Calmo'), findsOneWidget);
      expect(find.textContaining('Atualizado'), findsOneWidget);
      // Quatro tiles em dois pares + o cartão do gráfico.
      final tiles = find.byType(Card);
      expect(tiles, findsNWidgets(5));
      final a = tester.getRect(tiles.at(0));
      final b = tester.getRect(tiles.at(1));
      expect(a.height, b.height);
      expect(a.height, greaterThan(0));
      expect(b.right, lessThanOrEqualTo(390));
    });
  }

  testWidgets('shows the update time in 24h format regardless of device clock setting', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      permissao: true,
      resumo: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 68,
        mediaVfcHoje: 54,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime.now().copyWith(hour: 8, minute: 40),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Atualizado às 08:40'), findsOneWidget);
  });

  testWidgets('at 2.0x text scale the stat tiles stack vertically and keep whole values', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      permissao: true,
      textScale: 2.0,
      resumo: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 68,
        mediaVfcHoje: 54,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime.now(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final tiles = find.byType(Card);
    expect(tiles, findsAtLeastNWidgets(4));
    final a = tester.getRect(tiles.at(0));
    final b = tester.getRect(tiles.at(1));
    // Empilhados: o segundo começa abaixo do primeiro e ambos ocupam a largura toda.
    expect(b.top, greaterThanOrEqualTo(a.bottom));
    expect(a.width, closeTo(350, 1));
    expect(b.width, closeTo(350, 1));
  });

  group('fiel ao relógio', () {
    final hoje = DateTime.now();
    DateTime as_(int h, int m) => DateTime(hoje.year, hoje.month, hoje.day, h, m);

    testWidgets('shows the last reading with its time, the native resting HR and min/max', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        permissao: true,
        resumo: BiofeedbackSummary(
          ultimaFc: 71,
          ultimaFcEm: as_(14, 50),
          mediaFcHoje: 64,
          mediaVfcHoje: null,
          fcRepousoNativa: 55,
          fcRepousoNativaEm: as_(6, 30),
          fcMinHoje: 58,
          fcMaxHoje: 142,
          linhaDeBase: const LinhaDeBase(dias: 14, fcMedia: 62, fcDesvio: 2),
          usaVfc: false,
          estadoEstresse: EstadoEstresse.calmo,
          atualizadoEm: hoje,
        ),
        serie: SerieDia.agregar(
          dia: hoje,
          leituras: [
            HealthReading(valor: 58, timestamp: as_(4, 0)),
            HealthReading(valor: 142, timestamp: as_(12, 10)),
            HealthReading(valor: 71, timestamp: as_(14, 50)),
          ],
          emRepouso: (t) => t.hour != 12,
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('71'), findsWidgets);
      expect(find.text('às 14:50'), findsOneWidget);
      expect(find.text('pelo relógio'), findsOneWidget);
      expect(find.textContaining('58–142'), findsOneWidget);
      expect(find.text('relógio não enviou'), findsOneWidget);
      expect(find.textContaining('Detecção só pela frequência cardíaca'), findsOneWidget);
      expect(find.textContaining('Ao longo do dia · hoje'), findsOneWidget);
      expect(find.text('sua linha de base'), findsOneWidget);
    });

    testWidgets('explains how many days are missing while the baseline is being collected', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        permissao: true,
        diasNoHistorico: 4,
        resumo: BiofeedbackSummary(
          ultimaFc: 70,
          mediaFcHoje: 68,
          mediaVfcHoje: 54,
          estadoEstresse: EstadoEstresse.coletandoDados,
          atualizadoEm: hoje,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Linha de base: 4 de 7 dias'), findsOneWidget);
      expect(find.textContaining('Faltam 3 dias com leituras em repouso'), findsOneWidget);
      expect(find.text('sua linha de base'), findsNothing);
    });

    testWidgets('with the baseline ready but no resting reading today, says so instead of counting days', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        permissao: true,
        diasNoHistorico: 13,
        resumo: BiofeedbackSummary(
          ultimaFc: 120,
          mediaFcHoje: null,
          mediaVfcHoje: null,
          linhaDeBase: const LinhaDeBase(dias: 13, fcMedia: 62, fcDesvio: 2),
          estadoEstresse: EstadoEstresse.coletandoDados,
          atualizadoEm: hoje,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Linha de base: 7 de 7 dias'), findsOneWidget);
      expect(find.textContaining('Ainda sem leitura em repouso hoje'), findsOneWidget);
    });

    testWidgets('renders the empty chart when there is a summary but no series yet', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        permissao: true,
        resumo: BiofeedbackSummary(
          ultimaFc: null,
          mediaFcHoje: null,
          mediaVfcHoje: null,
          estadoEstresse: EstadoEstresse.coletandoDados,
          atualizadoEm: hoje,
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // O texto do gráfico vazio é pintado no canvas; a etiqueta de acessibilidade é o que dá
      // para verificar.
      expect(find.bySemanticsLabel(RegExp('sem leituras hoje ainda')), findsOneWidget);
      expect(find.text('sem leitura'), findsOneWidget);
      expect(find.text('sem leitura em repouso'), findsOneWidget);
    });
  });
}
