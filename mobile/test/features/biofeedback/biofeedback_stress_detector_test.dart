import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/biofeedback_stress_detector.dart';
import 'package:sincro_mobile/features/biofeedback/dia_repouso.dart';
import 'package:sincro_mobile/features/biofeedback/estado_estresse.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';
import 'package:sincro_mobile/features/biofeedback/treino_intervalo.dart';

void main() {
  final detector = BiofeedbackStressDetector();

  group('emRepouso', () {
    test('is false when a workout interval covers the timestamp', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 5),
        leiturasPassos: [],
        treinos: [
          TreinoIntervalo(inicio: DateTime(2026, 8, 3, 10, 0), fim: DateTime(2026, 8, 3, 10, 30)),
        ],
      );

      expect(resultado, false);
    });

    test('is false when steps in the surrounding 5-minute window reach the 15-step limiar', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 0),
        leiturasPassos: [
          HealthReading(valor: 15, timestamp: DateTime(2026, 8, 3, 10, 1)),
        ],
        treinos: [],
      );

      expect(resultado, false);
    });

    test('is true when steps in the surrounding window stay below the limiar and there is no workout', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 0),
        leiturasPassos: [
          HealthReading(valor: 14, timestamp: DateTime(2026, 8, 3, 10, 1)),
        ],
        treinos: [],
      );

      expect(resultado, true);
    });

    test('ignores steps outside the 5-minute window', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 0),
        leiturasPassos: [
          HealthReading(valor: 500, timestamp: DateTime(2026, 8, 3, 10, 10)),
        ],
        treinos: [],
      );

      expect(resultado, true);
    });

    test('is true with no steps and no workouts at all', () {
      final resultado = detector.emRepouso(
        timestamp: DateTime(2026, 8, 3, 10, 0),
        leiturasPassos: [],
        treinos: [],
      );

      expect(resultado, true);
    });
    test('attributes interval step samples proportionally to the overlap with the window', () {
      final detector = BiofeedbackStressDetector();
      final t = DateTime(2026, 9, 20, 9, 15);
      // 120 passos entre 09:00 e 09:20 (20 min): a janela 09:12:30–09:17:30 sobrepõe 5 min → 30
      // passos atribuídos, acima do limiar de 15 → não está em repouso.
      final caminhada = [
        HealthReading(
          valor: 120,
          timestamp: DateTime(2026, 9, 20, 9, 0),
          fim: DateTime(2026, 9, 20, 9, 20),
        ),
      ];
      expect(detector.emRepouso(timestamp: t, leiturasPassos: caminhada, treinos: []), isFalse);

      // 40 passos na mesma hora: 5/20 → 10 passos na janela, abaixo do limiar → em repouso.
      final poucosPassos = [
        HealthReading(
          valor: 40,
          timestamp: DateTime(2026, 9, 20, 9, 0),
          fim: DateTime(2026, 9, 20, 9, 20),
        ),
      ];
      expect(detector.emRepouso(timestamp: t, leiturasPassos: poucosPassos, treinos: []), isTrue);
    });

    test('an interval step sample that starts before the window still counts (no longer leaks as rest)', () {
      final detector = BiofeedbackStressDetector();
      final t = DateTime(2026, 9, 20, 9, 15);
      // Antes, só `timestamp` (09:00) era comparado com a janela 09:12:30–09:17:30 e a caminhada
      // inteira passava despercebida.
      final caminhada = [
        HealthReading(
          valor: 600,
          timestamp: DateTime(2026, 9, 20, 9, 0),
          fim: DateTime(2026, 9, 20, 9, 30),
        ),
      ];
      expect(detector.emRepouso(timestamp: t, leiturasPassos: caminhada, treinos: []), isFalse);
    });

    test('an interval step sample entirely outside the window contributes nothing', () {
      final detector = BiofeedbackStressDetector();
      final t = DateTime(2026, 9, 20, 9, 15);
      final antes = [
        HealthReading(
          valor: 900,
          timestamp: DateTime(2026, 9, 20, 8, 0),
          fim: DateTime(2026, 9, 20, 9, 10),
        ),
      ];
      expect(detector.emRepouso(timestamp: t, leiturasPassos: antes, treinos: []), isTrue);
    });
  });

  group('mediasEmRepouso', () {
    test('averages only the readings that are em repouso, discarding the rest', () {
      final resultado = detector.mediasEmRepouso(
        leiturasFc: [
          HealthReading(valor: 70, timestamp: DateTime(2026, 8, 3, 8, 0)), // em repouso
          HealthReading(valor: 120, timestamp: DateTime(2026, 8, 3, 10, 0)), // durante treino
        ],
        leiturasVfc: [
          HealthReading(valor: 40, timestamp: DateTime(2026, 8, 3, 8, 0)), // em repouso
        ],
        leiturasPassos: [],
        treinos: [
          TreinoIntervalo(inicio: DateTime(2026, 8, 3, 9, 45), fim: DateTime(2026, 8, 3, 10, 15)),
        ],
      );

      expect(resultado.mediaFc, 70);
      expect(resultado.mediaVfc, 40);
    });

    test('returns null for a metric with no readings em repouso', () {
      final resultado = detector.mediasEmRepouso(
        leiturasFc: [
          HealthReading(valor: 120, timestamp: DateTime(2026, 8, 3, 10, 0)),
        ],
        leiturasVfc: [],
        leiturasPassos: [],
        treinos: [
          TreinoIntervalo(inicio: DateTime(2026, 8, 3, 9, 45), fim: DateTime(2026, 8, 3, 10, 15)),
        ],
      );

      expect(resultado.mediaFc, isNull);
      expect(resultado.mediaVfc, isNull);
    });
  });

  group('detectar', () {
    List<DiaRepouso> historicoDeDias(int quantidade, {double fc = 70, double vfc = 45}) {
      return List.generate(
        quantidade,
        (i) => DiaRepouso(
          data: DateTime(2026, 7, 20 + i),
          mediaFcRepouso: fc,
          mediaVfcRepouso: vfc,
        ),
      );
    }

    test('is coletandoDados when there are fewer than 7 days of prior history', () {
      final estado = detector.detectar(
        mediaFcRepousoHoje: 100,
        mediaVfcRepousoHoje: 20,
        historico: historicoDeDias(6),
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.coletandoDados);
    });

    test('is coletandoDados when the baseline is ready but there is no resting reading today', () {
      final estado = detector.detectar(
        mediaFcRepousoHoje: null,
        mediaVfcRepousoHoje: null,
        historico: historicoDeDias(7),
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.coletandoDados);
    });

    test('is calmo when today is within the normal range', () {
      // Histórico com um pouco de variação real (não desvio zero), hoje bem próximo da média.
      final historico = [
        DiaRepouso(data: DateTime(2026, 7, 20), mediaFcRepouso: 68, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 21), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 22), mediaFcRepouso: 72, mediaVfcRepouso: 45),
        DiaRepouso(data: DateTime(2026, 7, 23), mediaFcRepouso: 69, mediaVfcRepouso: 47),
        DiaRepouso(data: DateTime(2026, 7, 24), mediaFcRepouso: 71, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 25), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 26), mediaFcRepouso: 69, mediaVfcRepouso: 45),
      ];

      final estado = detector.detectar(
        mediaFcRepousoHoje: 71,
        mediaVfcRepousoHoje: 45,
        historico: historico,
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.calmo);
    });

    test('is calmo when only FC is elevated but VFC stays normal', () {
      // Ambas as métricas têm variação real no histórico (desvio > 0), então isolar qual
      // condição dispara depende só do valor de hoje, não de um desvio zero mascarando o efeito.
      final historicoComVariacao = [
        DiaRepouso(data: DateTime(2026, 7, 20), mediaFcRepouso: 66, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 21), mediaFcRepouso: 68, mediaVfcRepouso: 45),
        DiaRepouso(data: DateTime(2026, 7, 22), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 23), mediaFcRepouso: 72, mediaVfcRepouso: 47),
        DiaRepouso(data: DateTime(2026, 7, 24), mediaFcRepouso: 74, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 25), mediaFcRepouso: 68, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 26), mediaFcRepouso: 70, mediaVfcRepouso: 45),
      ];
      // Média/desvio da FC: ~69.71 / ~2.49 -> limiar de elevado ~73.45. Média/desvio da VFC:
      // ~45.29 / ~1.03 -> limiar de reduzida ~43.74.

      final estado = detector.detectar(
        mediaFcRepousoHoje: 100, // >= 73.45: dispara a condição de FC sozinha
        mediaVfcRepousoHoje: 45, // > 43.74: NÃO dispara a condição de VFC
        historico: historicoComVariacao,
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.calmo);
    });

    test('is elevado when both FC is elevated and VFC is reduced together', () {
      final historico = [
        DiaRepouso(data: DateTime(2026, 7, 20), mediaFcRepouso: 66, mediaVfcRepouso: 50),
        DiaRepouso(data: DateTime(2026, 7, 21), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 7, 22), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 23), mediaFcRepouso: 72, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 24), mediaFcRepouso: 74, mediaVfcRepouso: 42),
        DiaRepouso(data: DateTime(2026, 7, 25), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 7, 26), mediaFcRepouso: 70, mediaVfcRepouso: 46),
      ];

      final estado = detector.detectar(
        mediaFcRepousoHoje: 110,
        mediaVfcRepousoHoje: 20,
        historico: historico,
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.elevado);
    });

    test('uses population standard deviation (÷N), not sample (÷N-1), for the threshold', () {
      // Teste discriminante: os demais casos passam com qualquer uma das duas convenções, então
      // uma troca acidental de `/ valores.length` para `/ (valores.length - 1)` em `_estatisticas`
      // não seria detectada. Aqui o valor de hoje cai exatamente na faixa entre os dois limiares.
      //
      // FC {66, 68, 70, 72, 74, 68, 70}: média 69.714, desvio populacional 2.4908 e amostral
      // 2.6904 -> limiar de FC elevada 73.4505 (populacional) contra 73.7498 (amostral).
      // A FC de hoje, 73.6, está entre os dois: dispara a condição só com variância populacional.
      //
      // A VFC de hoje (20) está muito abaixo do limiar de reduzida nas duas convenções (42.5495
      // e 42.2502), então ela nunca é o fator decisivo — quem decide o resultado é só a FC.
      final historico = [
        DiaRepouso(data: DateTime(2026, 7, 20), mediaFcRepouso: 66, mediaVfcRepouso: 50),
        DiaRepouso(data: DateTime(2026, 7, 21), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 7, 22), mediaFcRepouso: 70, mediaVfcRepouso: 46),
        DiaRepouso(data: DateTime(2026, 7, 23), mediaFcRepouso: 72, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 7, 24), mediaFcRepouso: 74, mediaVfcRepouso: 42),
        DiaRepouso(data: DateTime(2026, 7, 25), mediaFcRepouso: 68, mediaVfcRepouso: 48),
        DiaRepouso(data: DateTime(2026, 7, 26), mediaFcRepouso: 70, mediaVfcRepouso: 46),
      ];

      final estado = detector.detectar(
        mediaFcRepousoHoje: 73.6,
        mediaVfcRepousoHoje: 20,
        historico: historico,
        hoje: DateTime(2026, 8, 3),
      );

      // Com variância amostral este mesmo caso daria `calmo`.
      expect(estado, EstadoEstresse.elevado);
    });

    test('never triggers elevado from a metric whose baseline has zero standard deviation', () {
      // Todo o histórico com o mesmo valor de FC -> desvio-padrão zero -> a condição de FC
      // nunca é satisfeita, mesmo com um valor de hoje muito diferente.
      final estado = detector.detectar(
        mediaFcRepousoHoje: 200,
        mediaVfcRepousoHoje: 10,
        historico: historicoDeDias(7, fc: 70, vfc: 45),
        hoje: DateTime(2026, 8, 3),
      );

      // VFC também tem desvio zero no histórico, então nenhuma das duas condições dispara.
      expect(estado, EstadoEstresse.calmo);
    });

    test('does not count an entry for today toward the minimum days required for a baseline', () {
      // Só 6 dias anteriores de verdade (21-26/jul) mais uma entrada para hoje mesmo (03/ago).
      // Se a entrada de hoje entrasse na própria contagem, o histórico pareceria ter 7 dias
      // "anteriores" e a linha de base seria considerada pronta incorretamente.
      final historicoComEntradaDeHoje = [
        ...List.generate(
          6,
          (i) => DiaRepouso(data: DateTime(2026, 7, 21 + i), mediaFcRepouso: 70, mediaVfcRepouso: 45),
        ),
        DiaRepouso(data: DateTime(2026, 8, 3), mediaFcRepouso: 70, mediaVfcRepouso: 45),
      ];

      final estado = detector.detectar(
        mediaFcRepousoHoje: 70,
        mediaVfcRepousoHoje: 45,
        historico: historicoComEntradaDeHoje,
        hoje: DateTime(2026, 8, 3),
      );

      expect(estado, EstadoEstresse.coletandoDados);
    });
  });

  group('atualizarHistorico', () {
    test('appends a new entry for today when resting averages are available', () {
      final resultado = detector.atualizarHistorico(
        historicoAtual: [],
        hoje: DateTime(2026, 8, 3, 15, 0),
        mediaFcRepousoHoje: 70,
        mediaVfcRepousoHoje: 45,
      );

      expect(resultado, hasLength(1));
      expect(resultado.single.data, DateTime(2026, 8, 3));
      expect(resultado.single.mediaFcRepouso, 70);
      expect(resultado.single.mediaVfcRepouso, 45);
    });

    test('leaves the history unchanged when there is no resting reading today', () {
      final historicoAtual = [
        DiaRepouso(data: DateTime(2026, 8, 2), mediaFcRepouso: 68, mediaVfcRepouso: 44),
      ];

      final resultado = detector.atualizarHistorico(
        historicoAtual: historicoAtual,
        hoje: DateTime(2026, 8, 3, 15, 0),
        mediaFcRepousoHoje: null,
        mediaVfcRepousoHoje: 44,
      );

      expect(resultado, historicoAtual);
    });

    test('replaces an existing entry for today instead of duplicating it', () {
      final historicoAtual = [
        DiaRepouso(data: DateTime(2026, 8, 2), mediaFcRepouso: 68, mediaVfcRepouso: 44),
        DiaRepouso(data: DateTime(2026, 8, 3), mediaFcRepouso: 70, mediaVfcRepouso: 45),
      ];

      final resultado = detector.atualizarHistorico(
        historicoAtual: historicoAtual,
        hoje: DateTime(2026, 8, 3, 20, 0),
        mediaFcRepousoHoje: 72,
        mediaVfcRepousoHoje: 43,
      );

      expect(resultado, hasLength(2));
      final entradaHoje = resultado.firstWhere((d) => d.data == DateTime(2026, 8, 3));
      expect(entradaHoje.mediaFcRepouso, 72);
      expect(entradaHoje.mediaVfcRepouso, 43);
    });

    test('keeps only the 14 most recent days, pruning the oldest', () {
      final historicoAtual = List.generate(
        14,
        (i) => DiaRepouso(data: DateTime(2026, 7, 21 + i), mediaFcRepouso: 70, mediaVfcRepouso: 45),
      );

      final resultado = detector.atualizarHistorico(
        historicoAtual: historicoAtual,
        hoje: DateTime(2026, 8, 4),
        mediaFcRepousoHoje: 71,
        mediaVfcRepousoHoje: 46,
      );

      expect(resultado, hasLength(14));
      expect(resultado.first.data, DateTime(2026, 7, 22)); // 21 foi podado
      expect(resultado.last.data, DateTime(2026, 8, 4));
    });
  });

  group('detectar sem VFC (linha de base só de FC)', () {
    List<DiaRepouso> historicoSoFc() => [
          for (var i = 1; i <= 7; i++)
            DiaRepouso(data: DateTime(2026, 9, 20 - i), mediaFcRepouso: 60 + (i % 3) * 2.0),
        ];

    test('linhaDeBase is null with fewer than 7 prior days', () {
      final detector = BiofeedbackStressDetector();
      final base = detector.linhaDeBase(
        historico: historicoSoFc().sublist(0, 6),
        hoje: DateTime(2026, 9, 20),
      );
      expect(base, isNull);
    });

    test('linhaDeBase has FC stats but no VFC when the history has no VFC', () {
      final detector = BiofeedbackStressDetector();
      final base = detector.linhaDeBase(historico: historicoSoFc(), hoje: DateTime(2026, 9, 20))!;
      expect(base.dias, 7);
      expect(base.temVfc, isFalse);
      expect(base.fcMedia, closeTo(62.0, 0.01));
      expect(base.fcDesvio, greaterThan(0));
    });

    test('VFC only enters the baseline when at least 7 prior days have it', () {
      final detector = BiofeedbackStressDetector();
      final historico = [
        for (var i = 1; i <= 8; i++)
          DiaRepouso(
            data: DateTime(2026, 9, 20 - i),
            mediaFcRepouso: 60,
            mediaVfcRepouso: i <= 6 ? 45.0 : null,
          ),
      ];
      final base = detector.linhaDeBase(historico: historico, hoje: DateTime(2026, 9, 20))!;
      expect(base.temVfc, isFalse);
      expect(
        detector.usaVfc(mediaVfcRepousoHoje: 40, historico: historico, hoje: DateTime(2026, 9, 20)),
        isFalse,
      );
    });

    test('is calmo/elevado from FC alone with a 2σ margin when there is no VFC baseline', () {
      final detector = BiofeedbackStressDetector();
      final historico = historicoSoFc();
      final base = detector.linhaDeBase(historico: historico, hoje: DateTime(2026, 9, 20))!;
      final limiar15 = base.fcMedia + 1.5 * base.fcDesvio;
      final limiar20 = base.fcMedia + 2.0 * base.fcDesvio;

      // Entre 1,5σ e 2σ: com VFC seria "FC elevada", mas sem a confirmação da VFC ainda é calmo.
      expect(
        detector.detectar(
          mediaFcRepousoHoje: (limiar15 + limiar20) / 2,
          mediaVfcRepousoHoje: null,
          historico: historico,
          hoje: DateTime(2026, 9, 20),
        ),
        EstadoEstresse.calmo,
      );
      expect(
        detector.detectar(
          mediaFcRepousoHoje: limiar20 + 0.1,
          mediaVfcRepousoHoje: null,
          historico: historico,
          hoje: DateTime(2026, 9, 20),
        ),
        EstadoEstresse.elevado,
      );
    });

    test('falls back to FC alone when the baseline has VFC but today has none yet', () {
      final detector = BiofeedbackStressDetector();
      final historico = [
        for (var i = 1; i <= 7; i++)
          DiaRepouso(
            data: DateTime(2026, 9, 20 - i),
            mediaFcRepouso: 60 + (i % 3) * 2.0,
            mediaVfcRepouso: 45 + (i % 2) * 4.0,
          ),
      ];
      final base = detector.linhaDeBase(historico: historico, hoje: DateTime(2026, 9, 20))!;
      expect(base.temVfc, isTrue);
      final estado = detector.detectar(
        mediaFcRepousoHoje: base.fcMedia + 2.5 * base.fcDesvio,
        mediaVfcRepousoHoje: null,
        historico: historico,
        hoje: DateTime(2026, 9, 20),
      );
      expect(estado, EstadoEstresse.elevado);
    });
  });

  group('atualizarHistorico sem VFC', () {
    test('records the day with FC alone, leaving VFC null', () {
      final detector = BiofeedbackStressDetector();
      final atualizado = detector.atualizarHistorico(
        historicoAtual: const [],
        hoje: DateTime(2026, 9, 20, 15),
        mediaFcRepousoHoje: 63,
        mediaVfcRepousoHoje: null,
      );
      expect(atualizado.single.mediaFcRepouso, 63);
      expect(atualizado.single.mediaVfcRepouso, isNull);
    });
  });
}
