import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calming_games/breathing_rhythm.dart';

void main() {
  group('BreathingRhythm', () {
    const rhythm = BreathingRhythm();

    test('cycleSeconds is inhale + exhale', () {
      expect(rhythm.cycleSeconds, 10);
      const custom = BreathingRhythm(inhaleSeconds: 3, exhaleSeconds: 5);
      expect(custom.cycleSeconds, 8);
    });

    test('phase at key instants matches the spec exactly', () {
      expect(rhythm.phase(0), 0);
      expect(rhythm.phase(4), 1);
      expect(rhythm.phase(10), 0);
    });

    test('phase is periodic across multiple cycles', () {
      for (final t in [0.0, 1.5, 4.0, 6.3, 9.9]) {
        expect(rhythm.phase(t), closeTo(rhythm.phase(t + 10), 1e-9));
        expect(rhythm.phase(t), closeTo(rhythm.phase(t + 20), 1e-9));
      }
    });

    test('phase rises monotonically during inhale and falls during exhale', () {
      double? previous;
      for (double t = 0; t <= 4.0; t += 0.25) {
        final p = rhythm.phase(t);
        if (previous != null) expect(p, greaterThanOrEqualTo(previous));
        previous = p;
      }
      previous = null;
      for (double t = 4.0; t <= 10.0; t += 0.25) {
        final p = rhythm.phase(t);
        if (previous != null) expect(p, lessThanOrEqualTo(previous));
        previous = p;
      }
    });

    test('phase stays within [0, 1] at all times', () {
      for (double t = 0; t <= 30; t += 0.1) {
        final p = rhythm.phase(t);
        expect(p, inInclusiveRange(0.0, 1.0));
      }
    });

    test('phase has ~zero slope (smooth, no kink) at the turning points', () {
      const epsilon = 1e-4;
      for (final turningPoint in [0.0, 4.0, 10.0, 14.0]) {
        final before = rhythm.phase(turningPoint - epsilon);
        final at = rhythm.phase(turningPoint);
        final after = rhythm.phase(turningPoint + epsilon);
        final slopeBefore = (at - before) / epsilon;
        final slopeAfter = (after - at) / epsilon;
        expect(slopeBefore.abs(), lessThan(0.01));
        expect(slopeAfter.abs(), lessThan(0.01));
      }
    });

    test('phase is continuous around the inhale/exhale boundary', () {
      const epsilon = 1e-6;
      final justBefore = rhythm.phase(4.0 - epsilon);
      final justAfter = rhythm.phase(4.0 + epsilon);
      expect(justBefore, closeTo(1.0, 1e-3));
      expect(justAfter, closeTo(1.0, 1e-3));
    });

    test('isInhaling / label reflect the current half of the cycle', () {
      expect(rhythm.isInhaling(0), isTrue);
      expect(rhythm.label(0), 'Inspire');
      expect(rhythm.isInhaling(3.999), isTrue);
      expect(rhythm.isInhaling(4), isFalse);
      expect(rhythm.label(4), 'Solte');
      expect(rhythm.isInhaling(9.999), isFalse);
      // Next cycle repeats the same pattern.
      expect(rhythm.isInhaling(10), isTrue);
      expect(rhythm.label(10), 'Inspire');
    });

    test('negative t is treated as 0', () {
      expect(rhythm.phase(-1), rhythm.phase(0));
      expect(rhythm.phase(-100), rhythm.phase(0));
      expect(rhythm.isInhaling(-5), rhythm.isInhaling(0));
      expect(rhythm.label(-5), rhythm.label(0));
    });

    test('custom inhale/exhale durations still produce a valid smooth cycle', () {
      const custom = BreathingRhythm(inhaleSeconds: 2, exhaleSeconds: 3);
      expect(custom.phase(0), 0);
      expect(custom.phase(2), 1);
      expect(custom.phase(5), 0);
      expect(custom.phase(5), closeTo(custom.phase(0), 1e-9));
    });
  });

  test('non-finite t is treated as 0 and never yields NaN', () {
    const rhythm = BreathingRhythm();
    expect(rhythm.phase(double.nan), 0.0);
    expect(rhythm.phase(double.infinity), 0.0);
    expect(rhythm.phase(double.negativeInfinity), 0.0);
    expect(rhythm.label(double.nan), 'Inspire');
    expect(rhythm.isInhaling(double.infinity), isTrue);
  });
}
