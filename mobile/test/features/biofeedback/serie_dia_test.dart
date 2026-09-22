import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/biofeedback/health_reading.dart';
import 'package:sincro_mobile/features/biofeedback/serie_dia.dart';

void main() {
  final dia = DateTime(2026, 9, 20);
  HealthReading l(int h, int m, double v) =>
      HealthReading(valor: v, timestamp: DateTime(2026, 9, 20, h, m));

  group('SerieDia.agregar', () {
    test('groups readings into 5-minute buckets with mean, min and max', () {
      final serie = SerieDia.agregar(
        dia: dia,
        leituras: [l(8, 0, 60), l(8, 2, 70), l(8, 4, 80), l(8, 5, 100)],
        emRepouso: (_) => true,
      );
      expect(serie.pontos.length, 2);
      expect(serie.pontos[0].inicio, DateTime(2026, 9, 20, 8, 0));
      expect(serie.pontos[0].media, 70);
      expect(serie.pontos[0].minimo, 60);
      expect(serie.pontos[0].maximo, 80);
      expect(serie.pontos[1].inicio, DateTime(2026, 9, 20, 8, 5));
      expect(serie.pontos[1].media, 100);
    });

    test('sorts buckets chronologically regardless of input order', () {
      final serie = SerieDia.agregar(
        dia: dia,
        leituras: [l(15, 0, 70), l(7, 0, 60), l(11, 0, 65)],
        emRepouso: (_) => true,
      );
      expect(serie.pontos.map((p) => p.inicio.hour), [7, 11, 15]);
    });

    test('a bucket is at rest only when every reading in it is at rest', () {
      final serie = SerieDia.agregar(
        dia: dia,
        leituras: [l(9, 0, 60), l(9, 3, 120), l(10, 0, 62)],
        emRepouso: (t) => t.hour == 10 || t.minute == 0,
      );
      expect(serie.pontos[0].emRepouso, isFalse);
      expect(serie.pontos[1].emRepouso, isTrue);
    });

    test('ignores readings outside the day', () {
      final serie = SerieDia.agregar(
        dia: dia,
        leituras: [
          HealthReading(valor: 50, timestamp: DateTime(2026, 9, 19, 23, 59)),
          l(0, 0, 55),
          HealthReading(valor: 50, timestamp: DateTime(2026, 9, 21, 0, 0)),
        ],
        emRepouso: (_) => true,
      );
      expect(serie.pontos.length, 1);
      expect(serie.pontos.single.media, 55);
    });

    test('is empty when there are no readings', () {
      final serie = SerieDia.agregar(dia: dia, leituras: const [], emRepouso: (_) => true);
      expect(serie.vazia, isTrue);
      expect(serie.pico, isNull);
      expect(serie.vale, isNull);
      expect(serie.minimo, isNull);
      expect(serie.maximo, isNull);
    });
  });

  group('SerieDia extremes', () {
    test('pico is the bucket with the highest max, vale the one with the lowest min', () {
      final serie = SerieDia.agregar(
        dia: dia,
        leituras: [l(6, 0, 58), l(6, 1, 61), l(12, 0, 130), l(12, 2, 95), l(18, 0, 70)],
        emRepouso: (_) => true,
      );
      expect(serie.pico!.inicio.hour, 12);
      expect(serie.maximo, 130);
      expect(serie.vale!.inicio.hour, 6);
      expect(serie.minimo, 58);
    });

    test('ultimo is the most recent bucket', () {
      final serie = SerieDia.agregar(
        dia: dia,
        leituras: [l(6, 0, 58), l(18, 7, 70)],
        emRepouso: (_) => true,
      );
      expect(serie.ultimo!.inicio, DateTime(2026, 9, 20, 18, 5));
    });
  });

  group('SerieDia json', () {
    test('round-trips through toJson/fromJson', () {
      final original = SerieDia.agregar(
        dia: dia,
        leituras: [l(8, 0, 60), l(8, 2, 70), l(9, 0, 110)],
        emRepouso: (t) => t.hour == 8,
      );
      final copia = SerieDia.fromJson(original.toJson());
      expect(copia.dia, original.dia);
      expect(copia.pontos.length, 2);
      expect(copia.pontos[0].media, 65);
      expect(copia.pontos[0].minimo, 60);
      expect(copia.pontos[0].maximo, 70);
      expect(copia.pontos[0].emRepouso, isTrue);
      expect(copia.pontos[1].emRepouso, isFalse);
    });
  });
}
