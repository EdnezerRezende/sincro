import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_alert_service.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_cache.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_health_service.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_stress_detector.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_summary_calculator.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_sync_service.dart';
import 'package:sincro_mobile/features/biofeedback/dia_repouso.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';
import 'package:sincro_mobile/features/biofeedback/linha_de_base.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sincro_mobile/features/biofeedback/serie_dia.dart';
import 'package:sincro_mobile/features/biofeedback/treino_intervalo.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_card.dart';
import 'package:sincro_mobile/features/grounding_cards/grounding_cards_repository.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/sensory_profile_repository.dart';

class MockBiofeedbackHealthService extends Mock implements BiofeedbackHealthService {}

class MockBiofeedbackCache extends Mock implements BiofeedbackCache {}

class MockBiofeedbackAlertService extends Mock implements BiofeedbackAlertService {}

class MockSensoryProfileRepository extends Mock implements SensoryProfileRepository {}

class MockGroundingCardsRepository extends Mock implements GroundingCardsRepository {}

class FakeGroundingCard extends Fake implements GroundingCard {}

class FakeBiofeedbackSummary extends Fake implements BiofeedbackSummary {}

class FakeSerieDia extends Fake implements SerieDia {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeBiofeedbackSummary());
    registerFallbackValue(FakeGroundingCard());
    registerFallbackValue(FakeSerieDia());
    registerFallbackValue((inicio: DateTime(2000), fim: DateTime(2000)));
  });

  BiofeedbackSyncService buildService(
    MockBiofeedbackHealthService healthService,
    MockBiofeedbackCache cache,
    MockBiofeedbackAlertService alertService,
    MockSensoryProfileRepository sensoryProfileRepository, {
    List<HealthReading> passos = const [],
    List<TreinoIntervalo> treinos = const [],
    List<DiaRepouso> historico = const [],
    BiofeedbackSummary? resumoAnterior,
    bool ativo = true,
    int permissoesVersao = BiofeedbackCache.versaoPermissoesAtual,
    bool alertasAtivos = true,
    Map<String, dynamic>? perfilSensorial,
    List<GroundingCard> favoritosSugeridos = const [],
    List<GroundingCard> respiracaoAtivosSugeridos = const [],
    List<GroundingCard> todosAtivosSugeridos = const [],
    bool falharBuscaDeCards = false,
    DateTime? ultimoPreenchimento,
  }) {
    when(() => healthService.solicitarPermissao()).thenAnswer((_) async => true);
    when(() => healthService.lerPassos(any())).thenAnswer((_) async => passos);
    when(() => healthService.lerTreinos(any())).thenAnswer((_) async => treinos);
    when(() => healthService.lerFrequenciaRepousoNativa(any())).thenAnswer((_) async => null);
    when(() => cache.setSerieDia(any())).thenAnswer((_) async {});
    // Por padrão o preenchimento retroativo roda, mas as leituras mockadas são só de hoje — nenhum
    // dia anterior ganha entrada. Os testes que o exercitam de verdade passam leituras de outros dias.
    when(() => cache.getUltimoPreenchimento()).thenAnswer((_) async => ultimoPreenchimento);
    when(() => cache.setUltimoPreenchimento(any())).thenAnswer((_) async {});
    when(() => cache.isAtivo()).thenAnswer((_) async => ativo);
    when(() => cache.getPermissoesVersao()).thenAnswer((_) async => permissoesVersao);
    when(() => cache.setPermissoesVersao(any())).thenAnswer((_) async {});
    when(() => cache.getHistoricoRepouso()).thenAnswer((_) async => historico);
    when(() => cache.setHistoricoRepouso(any())).thenAnswer((_) async {});
    when(() => cache.getResumo()).thenAnswer((_) async => resumoAnterior);
    when(() => cache.setResumo(any())).thenAnswer((_) async {});
    when(() => cache.getAlertasAtivos()).thenAnswer((_) async => alertasAtivos);
    when(() => sensoryProfileRepository.get()).thenAnswer((_) async => perfilSensorial);
    when(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido')))
        .thenAnswer((_) async {});
    final groundingCardsRepository = MockGroundingCardsRepository();
    if (falharBuscaDeCards) {
      final erro = Exception('rede indisponível');
      when(() => groundingCardsRepository.listFavoritos()).thenThrow(erro);
      when(() => groundingCardsRepository.list(categoria: 'RESPIRACAO')).thenThrow(erro);
      when(() => groundingCardsRepository.list()).thenThrow(erro);
    } else {
      when(() => groundingCardsRepository.listFavoritos())
          .thenAnswer((_) async => favoritosSugeridos);
      when(() => groundingCardsRepository.list(categoria: 'RESPIRACAO'))
          .thenAnswer((_) async => respiracaoAtivosSugeridos);
      when(() => groundingCardsRepository.list())
          .thenAnswer((_) async => todosAtivosSugeridos);
    }
    return BiofeedbackSyncService(
      healthService,
      cache,
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
      alertService,
      sensoryProfileRepository,
      groundingCardsRepository,
    );
  }

  List<DiaRepouso> historicoEstavelElevando() => [
        DiaRepouso(data: DateTime(2026, 7, 27), mediaFcRepouso: 66, mediaVfcRepouso: 50),
        DiaRepouso(data: DateTime(2026, 7, 28), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 7, 29), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 30), mediaFcRepouso: 72, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 31), mediaFcRepouso: 74, mediaVfcRepouso: 42),
        DiaRepouso(data: DateTime(2026, 8, 1), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 8, 2), mediaFcRepouso: 70, mediaVfcRepouso: 46),
      ];

  test('sends the alert when the state transitions into elevado with tolerancia PADRAO', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 70,
        mediaVfcHoje: 45,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
    );

    await service.sincronizar(agora: agora);

    verify(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido'))).called(1);
  });

  test('does not send the alert when already elevado before this cycle', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: 110,
        mediaFcHoje: 110,
        mediaVfcHoje: 20,
        estadoEstresse: EstadoEstresse.elevado,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido')));
    // Sem transição para elevado (já estava elevado), a leitura de rede nem deveria acontecer.
    verifyNever(() => sensoryProfileRepository.get());
  });

  test('does not send the alert or read the sensory profile when the resulting state is not elevado', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer((_) async => []);
    when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => []);
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: null,
        mediaFcHoje: null,
        mediaVfcHoje: null,
        estadoEstresse: EstadoEstresse.coletandoDados,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido')));
    // Sem transição para elevado, a leitura de rede nem deveria acontecer.
    verifyNever(() => sensoryProfileRepository.get());
  });

  test('does not send the alert when alertasAtivos is false, and skips the network read', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 70,
        mediaVfcHoje: 45,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      alertasAtivos: false,
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido')));
    verifyNever(() => sensoryProfileRepository.get());
  });

  test('does not send the alert when tolerancia is not PADRAO', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 70,
        mediaVfcHoje: 45,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'HORARIO_ESPECIFICO'},
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido')));
  });

  test('treats a failed sensory-profile read as no-alert rather than throwing', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 70,
        mediaVfcHoje: 45,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
    );
    when(() => sensoryProfileRepository.get()).thenThrow(Exception('rede indisponível'));

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    verifyNever(() => alertService.mostrarAlerta(cardSugerido: any(named: 'cardSugerido')));
  });

  test('still saves the summary and history correctly alongside the alert logic', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 80, timestamp: DateTime(2026, 8, 3, 9, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 45, timestamp: DateTime(2026, 8, 3, 9, 0))],
    );
    final service = buildService(healthService, cache, alertService, sensoryProfileRepository);

    await service.sincronizar(agora: agora);

    final captured = verify(() => cache.setResumo(captureAny())).captured;
    final salvo = captured.single as BiofeedbackSummary;
    expect(salvo.ultimaFc, 80);
    expect(salvo.mediaFcHoje, 80);
    expect(salvo.mediaVfcHoje, 45);
    expect(salvo.atualizadoEm, agora);
  });

  test('saves an all-null summary with coletandoDados when there are no readings yet', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer((_) async => []);
    when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => []);
    final service = buildService(healthService, cache, alertService, sensoryProfileRepository);

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    final captured = verify(() => cache.setResumo(captureAny())).captured;
    final salvo = captured.single as BiofeedbackSummary;
    expect(salvo.ultimaFc, isNull);
    expect(salvo.estadoEstresse, EstadoEstresse.coletandoDados);
  });

  test('discards readings during a workout when computing the resting history entry', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [
        HealthReading(valor: 70, timestamp: DateTime(2026, 8, 3, 8, 0)), // em repouso
        HealthReading(valor: 150, timestamp: DateTime(2026, 8, 3, 10, 0)), // durante treino
      ],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [
        HealthReading(valor: 45, timestamp: DateTime(2026, 8, 3, 8, 0)), // em repouso
        HealthReading(valor: 15, timestamp: DateTime(2026, 8, 3, 10, 0)), // durante treino
      ],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      treinos: [
        TreinoIntervalo(inicio: DateTime(2026, 8, 3, 9, 45), fim: DateTime(2026, 8, 3, 10, 15)),
      ],
    );

    await service.sincronizar(agora: agora);

    final captured = verify(() => cache.setHistoricoRepouso(captureAny())).captured;
    final historicoSalvo = captured.single as List<DiaRepouso>;
    expect(historicoSalvo, hasLength(1));
    // Só a leitura em repouso (70) entra na média do dia — a de 150 durante o treino é descartada.
    expect(historicoSalvo.single.mediaFcRepouso, 70);

    // O resumo salvo (o que a tela de detalhe mostra) também precisa refletir só o repouso: se
    // `mediaFcHoje`/`mediaVfcHoje` voltassem a ser a média bruta do dia (110 e 30, incluindo as
    // leituras durante o treino), o número exibido não bateria mais com o estado calmo/elevado
    // calculado a partir do mesmo filtro — exatamente a incoerência que este ajuste elimina.
    final resumoSalvo =
        verify(() => cache.setResumo(captureAny())).captured.single as BiofeedbackSummary;
    expect(resumoSalvo.mediaFcHoje, 70);
    expect(resumoSalvo.mediaVfcHoje, 45);
  });

  test('mediaFcHoje/mediaVfcHoje are null when every reading falls during a workout, even '
      'though ultimaFc (last raw sample) is still available', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 150, timestamp: DateTime(2026, 8, 3, 10, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 15, timestamp: DateTime(2026, 8, 3, 10, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      treinos: [
        TreinoIntervalo(inicio: DateTime(2026, 8, 3, 9, 45), fim: DateTime(2026, 8, 3, 10, 15)),
      ],
    );

    await service.sincronizar(agora: agora);

    final resumoSalvo =
        verify(() => cache.setResumo(captureAny())).captured.single as BiofeedbackSummary;
    expect(resumoSalvo.ultimaFc, 150);
    expect(resumoSalvo.mediaFcHoje, isNull);
    expect(resumoSalvo.mediaVfcHoje, isNull);
  });

  test('detects elevado when today is far outside a stable 7-day baseline', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
    );

    await service.sincronizar(agora: agora);

    final captured = verify(() => cache.setResumo(captureAny())).captured;
    final salvo = captured.single as BiofeedbackSummary;
    expect(salvo.estadoEstresse, EstadoEstresse.elevado);
  });

  test('includes a favorited card in the alert body when the state transitions into elevado', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final favorito = GroundingCard(
      id: 'fav-1',
      titulo: 'Respiração 4-7-8',
      categoria: 'RESPIRACAO',
      conteudo: 'Conteúdo',
      ativo: true,
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 70,
        mediaVfcHoje: 45,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
      favoritosSugeridos: [favorito],
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    final captured =
        verify(() => alertService.mostrarAlerta(cardSugerido: captureAny(named: 'cardSugerido')))
            .captured;
    final cardSugerido = captured.single as GroundingCard?;
    expect(cardSugerido?.id, 'fav-1');
  });

  test('alerts with no suggested card when every grounding-card lookup fails', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidade(any())).thenAnswer(
      (_) async => [HealthReading(valor: 20, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    final service = buildService(
      healthService,
      cache,
      alertService,
      sensoryProfileRepository,
      historico: historicoEstavelElevando(),
      resumoAnterior: BiofeedbackSummary(
        ultimaFc: 70,
        mediaFcHoje: 70,
        mediaVfcHoje: 45,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 8, 3, 14, 0),
      ),
      perfilSensorial: {'toleranciaNotificacao': 'PADRAO'},
      falharBuscaDeCards: true,
    );

    await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

    final captured =
        verify(() => alertService.mostrarAlerta(cardSugerido: captureAny(named: 'cardSugerido')))
            .captured;
    expect(captured.single, isNull);
  });

  group('upgrade de permissões', () {
    void stubLeiturasVazias(MockBiofeedbackHealthService healthService) {
      when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer((_) async => []);
      when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => []);
    }

    test('requests the new permissions once for a user activated on an older version', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      stubLeiturasVazias(healthService);
      // Usuário da Fase 1: já ativo, mas sem nenhuma versão de permissão gravada.
      final service = buildService(
        healthService,
        cache,
        alertService,
        sensoryProfileRepository,
        permissoesVersao: 0,
      );

      await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

      verify(() => healthService.solicitarPermissao()).called(1);
      verify(() => cache.setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual)).called(1);
    });

    test('requests permissions before reading any health data', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      stubLeiturasVazias(healthService);
      final service = buildService(
        healthService,
        cache,
        alertService,
        sensoryProfileRepository,
        permissoesVersao: 0,
      );

      await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

      // Pedir depois de ler não adiantaria nada: as leituras desta rodada já teriam voltado
      // vazias para os tipos ainda não autorizados.
      verifyInOrder([
        () => healthService.solicitarPermissao(),
        () => healthService.lerFrequenciaCardiaca(any()),
      ]);
    });

    test('does not request permissions again once the current version is recorded', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      stubLeiturasVazias(healthService);
      final service = buildService(healthService, cache, alertService, sensoryProfileRepository);

      await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

      verifyNever(() => healthService.solicitarPermissao());
      verifyNever(() => cache.setPermissoesVersao(any()));
    });

    test('does not request permissions when biofeedback is not active', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      stubLeiturasVazias(healthService);
      final service = buildService(
        healthService,
        cache,
        alertService,
        sensoryProfileRepository,
        ativo: false,
        permissoesVersao: 0,
      );

      await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

      verifyNever(() => healthService.solicitarPermissao());
    });

    test('records the version even when the permission request is denied', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      stubLeiturasVazias(healthService);
      final service = buildService(
        healthService,
        cache,
        alertService,
        sensoryProfileRepository,
        permissoesVersao: 0,
      );
      when(() => healthService.solicitarPermissao()).thenAnswer((_) async => false);

      await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

      // Uma recusa deliberada não pode virar um pedido a cada ciclo de sincronização.
      verify(() => cache.setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual)).called(1);
    });

    test('still syncs, and records the version, when the permission request throws', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      stubLeiturasVazias(healthService);
      final service = buildService(
        healthService,
        cache,
        alertService,
        sensoryProfileRepository,
        permissoesVersao: 0,
      );
      when(() => healthService.solicitarPermissao()).thenThrow(Exception('sem activity'));

      await service.sincronizar(agora: DateTime(2026, 8, 3, 15, 0));

      verify(() => cache.setPermissoesVersao(BiofeedbackCache.versaoPermissoesAtual)).called(1);
      verify(() => cache.setResumo(any())).called(1);
    });
  });

  group('preenchimento retroativo do histórico', () {
    final agora = DateTime(2026, 9, 20, 15, 0);

    /// 14 dias de leituras em repouso (3 por dia), sem VFC, mais as de hoje.
    List<HealthReading> fcDeDuasSemanas() => [
          for (var i = 0; i <= 14; i++)
            for (final hora in [3, 9, 21])
              HealthReading(
                valor: 60 + (i % 4) * 2.0,
                timestamp: DateTime(2026, 9, 20 - i, hora),
              ),
        ];

    test('fills the missing prior days from the platform on the first sync, so the baseline is '
        'ready immediately instead of "0 de 7 dias"', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      final leituras = fcDeDuasSemanas();
      when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer((_) async => leituras);
      when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => const []);
      final service = buildService(healthService, cache, alertService, sensoryProfileRepository);

      await service.sincronizar(agora: agora);

      final historico = verify(() => cache.setHistoricoRepouso(captureAny())).captured.single
          as List<DiaRepouso>;
      // 13 dias anteriores + hoje = a janela de 14 entradas.
      expect(historico.length, 14);
      expect(historico.first.data, DateTime(2026, 9, 7));
      expect(historico.last.data, DateTime(2026, 9, 20));
      expect(historico.every((d) => d.mediaVfcRepouso == null), isTrue);
      final resumo = verify(() => cache.setResumo(captureAny())).captured.single
          as BiofeedbackSummary;
      expect(resumo.estadoEstresse, isNot(EstadoEstresse.coletandoDados));
      expect(resumo.linhaDeBase, isNotNull);
      // 13 dias preenchidos: o contador da tela não oscila na sincronização seguinte.
      expect(resumo.linhaDeBase!.dias, 13);
      expect(resumo.usaVfc, isFalse);
      verify(() => cache.setUltimoPreenchimento(agora)).called(1);
      // Uma leitura em lote por tipo (14 dias), além da de hoje.
      verify(() => healthService.lerFrequenciaCardiaca(any())).called(2);
    });

    test('skips the batch read when the backfill already ran today', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      when(() => healthService.lerFrequenciaCardiaca(any()))
          .thenAnswer((_) async => fcDeDuasSemanas());
      when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => const []);
      final service = buildService(
        healthService,
        cache,
        alertService,
        sensoryProfileRepository,
        ultimoPreenchimento: DateTime(2026, 9, 20, 8),
      );

      await service.sincronizar(agora: agora);

      verify(() => healthService.lerFrequenciaCardiaca(any())).called(1);
      verifyNever(() => cache.setUltimoPreenchimento(any()));
      final historico = verify(() => cache.setHistoricoRepouso(captureAny())).captured.single
          as List<DiaRepouso>;
      expect(historico.length, 1);
    });

    test('does nothing when no prior day is missing', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      when(() => healthService.lerFrequenciaCardiaca(any()))
          .thenAnswer((_) async => fcDeDuasSemanas());
      when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => const []);
      final completo = [
        for (var i = 1; i <= 13; i++)
          DiaRepouso(data: DateTime(2026, 9, 20 - i), mediaFcRepouso: 62),
      ];
      final service = buildService(
        healthService,
        cache,
        alertService,
        sensoryProfileRepository,
        historico: completo,
      );

      await service.sincronizar(agora: agora);

      verify(() => healthService.lerFrequenciaCardiaca(any())).called(1);
      verifyNever(() => cache.getUltimoPreenchimento());
    });

    test('keeps the history and finishes the sync when the batch read fails', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      var chamadas = 0;
      when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer((_) async {
        chamadas++;
        if (chamadas == 2) throw Exception('Health Connect indisponível');
        return [HealthReading(valor: 64, timestamp: DateTime(2026, 9, 20, 9))];
      });
      when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => const []);
      final service = buildService(healthService, cache, alertService, sensoryProfileRepository);

      await service.sincronizar(agora: agora);

      verifyNever(() => cache.setUltimoPreenchimento(any()));
      final historico = verify(() => cache.setHistoricoRepouso(captureAny())).captured.single
          as List<DiaRepouso>;
      expect(historico.length, 1);
      verify(() => cache.setResumo(any())).called(1);
    });
  });

  group('resumo fiel ao relógio', () {
    final agora = DateTime(2026, 9, 20, 15, 0);

    test('carries the latest reading with its time, min/max of the day and the native resting HR',
        () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
        (_) async => [
          HealthReading(valor: 58, timestamp: DateTime(2026, 9, 20, 4)),
          HealthReading(valor: 142, timestamp: DateTime(2026, 9, 20, 12, 10)),
          HealthReading(valor: 71, timestamp: DateTime(2026, 9, 20, 14, 50)),
        ],
      );
      when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => const []);
      final service = buildService(
        healthService,
        cache,
        alertService,
        sensoryProfileRepository,
        treinos: [
          TreinoIntervalo(inicio: DateTime(2026, 9, 20, 12), fim: DateTime(2026, 9, 20, 12, 30)),
        ],
      );
      when(() => healthService.lerFrequenciaRepousoNativa(any())).thenAnswer(
        (_) async => HealthReading(valor: 55, timestamp: DateTime(2026, 9, 20, 6, 30)),
      );

      await service.sincronizar(agora: agora);

      final resumo = verify(() => cache.setResumo(captureAny())).captured.single
          as BiofeedbackSummary;
      expect(resumo.ultimaFc, 71);
      expect(resumo.ultimaFcEm, DateTime(2026, 9, 20, 14, 50));
      expect(resumo.fcMinHoje, 58);
      expect(resumo.fcMaxHoje, 142);
      expect(resumo.fcRepousoNativa, 55);
      expect(resumo.fcRepousoNativaEm, DateTime(2026, 9, 20, 6, 30));
      // A média em repouso exclui o treino.
      expect(resumo.mediaFcHoje, closeTo(64.5, 0.01));
      final periodo = verify(() => healthService.lerFrequenciaRepousoNativa(captureAny()))
          .captured
          .single as ({DateTime inicio, DateTime fim});
      expect(periodo.fim, agora);
      expect(periodo.inicio, agora.subtract(const Duration(hours: 48)));

      final serie = verify(() => cache.setSerieDia(captureAny())).captured.single as SerieDia;
      expect(serie.pontos.length, 3);
      expect(serie.pontos[1].emRepouso, isFalse);
      expect(serie.pontos[0].emRepouso, isTrue);
      expect(serie.dia, DateTime(2026, 9, 20));
    });

    test('a failing native resting-HR read leaves the field null and the sync completes', () async {
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
        (_) async => [HealthReading(valor: 66, timestamp: DateTime(2026, 9, 20, 9))],
      );
      when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => const []);
      final service = buildService(healthService, cache, alertService, sensoryProfileRepository);
      when(() => healthService.lerFrequenciaRepousoNativa(any()))
          .thenThrow(Exception('permissão negada'));

      await service.sincronizar(agora: agora);

      final resumo = verify(() => cache.setResumo(captureAny())).captured.single
          as BiofeedbackSummary;
      expect(resumo.fcRepousoNativa, isNull);
      expect(resumo.ultimaFc, 66);
    });
  });

  group('lacunas do crítico (rodada 1)', () {
    test('a single step sample covering the whole day does not turn the day into activity', () {
      final detector = BiofeedbackStressDetector();
      final diaInteiro = [
        HealthReading(
          valor: 8000,
          timestamp: DateTime(2026, 9, 19),
          fim: DateTime(2026, 9, 20),
        ),
      ];
      expect(
        detector.emRepouso(
          timestamp: DateTime(2026, 9, 19, 3),
          leiturasPassos: diaInteiro,
          treinos: [],
        ),
        isTrue,
      );
      // Uma amostra de até 1 h continua sendo atribuída proporcionalmente.
      final umaHora = [
        HealthReading(
          valor: 600,
          timestamp: DateTime(2026, 9, 19, 9),
          fim: DateTime(2026, 9, 19, 10),
        ),
      ];
      expect(
        detector.emRepouso(
          timestamp: DateTime(2026, 9, 19, 9, 30),
          leiturasPassos: umaHora,
          treinos: [],
        ),
        isFalse,
      );
    });

    test('backfill dates its entries by calendar day even across a DST change', () async {
      // 2026-03-08 é a virada do horário de verão em America/New_York; o teste força o cálculo
      // com um `agora` logo depois dela. Sem fuso com DST na máquina o teste continua válido
      // (as datas só precisam ser meia-noite local do dia certo).
      final healthService = MockBiofeedbackHealthService();
      final cache = MockBiofeedbackCache();
      final alertService = MockBiofeedbackAlertService();
      final sensoryProfileRepository = MockSensoryProfileRepository();
      final agora = DateTime(2026, 3, 9, 15);
      when(() => healthService.lerFrequenciaCardiaca(any())).thenAnswer(
        (_) async => [
          for (var i = 0; i <= 13; i++)
            HealthReading(valor: 60, timestamp: DateTime(2026, 3, 9 - i, 3)),
        ],
      );
      when(() => healthService.lerVariabilidade(any())).thenAnswer((_) async => const []);
      final service = buildService(healthService, cache, alertService, sensoryProfileRepository);

      await service.sincronizar(agora: agora);

      final historico = verify(() => cache.setHistoricoRepouso(captureAny())).captured.single
          as List<DiaRepouso>;
      expect(historico.length, 14);
      for (final d in historico) {
        expect(d.data.hour, 0, reason: 'entrada ${d.data} deveria ser meia-noite local');
      }
      expect(historico.map((d) => d.data.day).toList(), [24, 25, 26, 27, 28, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('a corrupted backfill stamp is treated as "never ran" instead of throwing', () async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      await SharedPreferencesAsync().setString(
        'biofeedback_historico_preenchido_em',
        'nao-e-data',
      );
      await SharedPreferencesAsync().setString('biofeedback_serie_dia', '{corrompido');
      final cache = BiofeedbackCache();
      expect(await cache.getUltimoPreenchimento(), isNull);
      expect(await cache.getSerieDia(), isNull);
    });

    test('faixaRepousoFc uses the same margin that decided the state', () {
      const base = LinhaDeBase(dias: 10, fcMedia: 60, fcDesvio: 2);
      final comVfc = BiofeedbackSummary(
        ultimaFc: null,
        mediaFcHoje: null,
        mediaVfcHoje: null,
        linhaDeBase: base,
        usaVfc: true,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 9, 20),
      );
      final soFc = BiofeedbackSummary(
        ultimaFc: null,
        mediaFcHoje: null,
        mediaVfcHoje: null,
        linhaDeBase: base,
        usaVfc: false,
        estadoEstresse: EstadoEstresse.calmo,
        atualizadoEm: DateTime(2026, 9, 20),
      );
      expect(comVfc.faixaRepousoFc, (minimo: 57.0, maximo: 63.0));
      expect(soFc.faixaRepousoFc, (minimo: 56.0, maximo: 64.0));
    });
  });
}
