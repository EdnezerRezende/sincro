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
import 'package:sincro_mobile/features/biofeedback/treino_intervalo.dart';
import 'package:sincro_mobile/features/onboarding/anamnese/sensory_profile_repository.dart';

class MockBiofeedbackHealthService extends Mock implements BiofeedbackHealthService {}

class MockBiofeedbackCache extends Mock implements BiofeedbackCache {}

class MockBiofeedbackAlertService extends Mock implements BiofeedbackAlertService {}

class MockSensoryProfileRepository extends Mock implements SensoryProfileRepository {}

class FakeBiofeedbackSummary extends Fake implements BiofeedbackSummary {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeBiofeedbackSummary());
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
  }) {
    when(() => healthService.solicitarPermissao()).thenAnswer((_) async => true);
    when(() => healthService.lerPassosHoje()).thenAnswer((_) async => passos);
    when(() => healthService.lerTreinosHoje()).thenAnswer((_) async => treinos);
    when(() => cache.isAtivo()).thenAnswer((_) async => ativo);
    when(() => cache.getPermissoesVersao()).thenAnswer((_) async => permissoesVersao);
    when(() => cache.setPermissoesVersao(any())).thenAnswer((_) async {});
    when(() => cache.getHistoricoRepouso()).thenAnswer((_) async => historico);
    when(() => cache.setHistoricoRepouso(any())).thenAnswer((_) async {});
    when(() => cache.getResumo()).thenAnswer((_) async => resumoAnterior);
    when(() => cache.setResumo(any())).thenAnswer((_) async {});
    when(() => cache.getAlertasAtivos()).thenAnswer((_) async => alertasAtivos);
    when(() => sensoryProfileRepository.get()).thenAnswer((_) async => perfilSensorial);
    when(() => alertService.mostrarAlerta()).thenAnswer((_) async {});
    return BiofeedbackSyncService(
      healthService,
      cache,
      BiofeedbackSummaryCalculator(),
      BiofeedbackStressDetector(),
      alertService,
      sensoryProfileRepository,
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
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
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

    verify(() => alertService.mostrarAlerta()).called(1);
  });

  test('does not send the alert when already elevado before this cycle', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
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

    verifyNever(() => alertService.mostrarAlerta());
    // Sem transição para elevado (já estava elevado), a leitura de rede nem deveria acontecer.
    verifyNever(() => sensoryProfileRepository.get());
  });

  test('does not send the alert or read the sensory profile when the resulting state is not elevado', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer((_) async => []);
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer((_) async => []);
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

    verifyNever(() => alertService.mostrarAlerta());
    // Sem transição para elevado, a leitura de rede nem deveria acontecer.
    verifyNever(() => sensoryProfileRepository.get());
  });

  test('does not send the alert when alertasAtivos is false, and skips the network read', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
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

    verifyNever(() => alertService.mostrarAlerta());
    verifyNever(() => sensoryProfileRepository.get());
  });

  test('does not send the alert when tolerancia is not PADRAO', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
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

    verifyNever(() => alertService.mostrarAlerta());
  });

  test('treats a failed sensory-profile read as no-alert rather than throwing', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
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

    verifyNever(() => alertService.mostrarAlerta());
  });

  test('still saves the summary and history correctly alongside the alert logic', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 80, timestamp: DateTime(2026, 8, 3, 9, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
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
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer((_) async => []);
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer((_) async => []);
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
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [
        HealthReading(valor: 70, timestamp: DateTime(2026, 8, 3, 8, 0)), // em repouso
        HealthReading(valor: 150, timestamp: DateTime(2026, 8, 3, 10, 0)), // durante treino
      ],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 45, timestamp: DateTime(2026, 8, 3, 8, 0))],
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
  });

  test('detects elevado when today is far outside a stable 7-day baseline', () async {
    final healthService = MockBiofeedbackHealthService();
    final cache = MockBiofeedbackCache();
    final alertService = MockBiofeedbackAlertService();
    final sensoryProfileRepository = MockSensoryProfileRepository();
    final agora = DateTime(2026, 8, 3, 15, 0);
    when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer(
      (_) async => [HealthReading(valor: 110, timestamp: DateTime(2026, 8, 3, 8, 0))],
    );
    when(() => healthService.lerVariabilidadeHoje()).thenAnswer(
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

  group('upgrade de permissões', () {
    void stubLeiturasVazias(MockBiofeedbackHealthService healthService) {
      when(() => healthService.lerFrequenciaCardiacaHoje()).thenAnswer((_) async => []);
      when(() => healthService.lerVariabilidadeHoje()).thenAnswer((_) async => []);
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
        () => healthService.lerFrequenciaCardiacaHoje(),
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
}
