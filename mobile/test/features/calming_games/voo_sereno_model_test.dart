import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calming_games/breathing_rhythm.dart';
import 'package:sincro_mobile/features/calming_games/voo_sereno_model.dart';

void main() {
  group('VooSerenoModel', () {
    test('starts centered with no velocity and no rings', () {
      final model = VooSerenoModel(seed: 1);
      expect(model.altitude, 0.5);
      expect(model.verticalVelocity, 0);
      expect(model.touchTarget, isNull);
      expect(model.rings, isEmpty);
      expect(model.ringsPassed, 0);
      expect(model.lastHitRing, isNull);
      expect(model.hitThisFrame, isFalse);
    });

    test('update clamps dt to 0.1s so a background pause never jumps', () {
      final model = VooSerenoModel(seed: 1);
      model.update(5.0);
      expect(model.elapsed, closeTo(0.1, 1e-9));

      final model2 = VooSerenoModel(seed: 1);
      model2.update(-3.0);
      expect(model2.elapsed, 0.0);
    });

    test('setTarget clamps to [0, 1]', () {
      final model = VooSerenoModel(seed: 1);
      model.setTarget(1.5);
      expect(model.touchTarget, 1.0);
      model.setTarget(-0.5);
      expect(model.touchTarget, 0.0);
      model.setTarget(0.4);
      expect(model.touchTarget, 0.4);
    });

    test('releaseTouch makes the plane follow the breathing wave again', () {
      final model = VooSerenoModel(seed: 1);
      model.setTarget(0.9);
      expect(model.touchTarget, isNotNull);
      model.releaseTouch();
      expect(model.touchTarget, isNull);

      // Drive a while with no touch: altitude should track breathingAltitude
      // (converge close to it, never using a stale touch target).
      // 2020 passos (não 2000) para NÃO cair exatamente num ponto de virada da
      // respiração, onde o erro é artificialmente pequeno; a tolerância 0.05
      // reflete o atraso real da mola crítica (~0.036) seguindo a onda.
      for (int i = 0; i < 2020; i++) {
        model.update(0.05);
      }
      expect(model.altitude, closeTo(model.breathingAltitude, 0.05));
    });

    test('spring never overshoots a constant target approached from rest', () {
      final model = VooSerenoModel(seed: 1);
      model.setTarget(0.9); // approaching from 0.5 (below target)
      double? previous = model.altitude;
      for (int i = 0; i < 500; i++) {
        model.update(0.02);
        expect(model.altitude, lessThanOrEqualTo(0.9 + 1e-9));
        expect(model.altitude, greaterThanOrEqualTo(previous!));
        previous = model.altitude;
      }
      expect(model.altitude, closeTo(0.9, 1e-3));

      final modelDown = VooSerenoModel(seed: 1);
      modelDown.setTarget(0.1); // approaching from 0.5 (above target)
      double? previousDown = modelDown.altitude;
      for (int i = 0; i < 500; i++) {
        modelDown.update(0.02);
        expect(modelDown.altitude, greaterThanOrEqualTo(0.1 - 1e-9));
        expect(modelDown.altitude, lessThanOrEqualTo(previousDown!));
        previousDown = modelDown.altitude;
      }
      expect(modelDown.altitude, closeTo(0.1, 1e-3));
    });

    test('pitchRadians is clamped to +-12 degrees and follows vertical velocity sign', () {
      final model = VooSerenoModel(seed: 1);
      model.setTarget(1.0);
      // Push several large-dt steps to try to build up velocity beyond the limit.
      for (int i = 0; i < 10; i++) {
        model.update(0.1);
      }
      const maxPitch = 12 * 3.141592653589793 / 180;
      expect(model.pitchRadians.abs(), lessThanOrEqualTo(maxPitch + 1e-9));
      expect(model.verticalVelocity, greaterThan(0));
      expect(model.pitchRadians, greaterThan(0));
    });

    test('deterministic ring y sequence with the same seed', () {
      final a = VooSerenoModel(seed: 42);
      final b = VooSerenoModel(seed: 42);
      for (int i = 0; i < 400; i++) {
        a.update(0.1);
        b.update(0.1);
      }
      expect(a.rings.length, b.rings.length);
      for (int i = 0; i < a.rings.length; i++) {
        expect(a.rings[i].y, b.rings[i].y);
        expect(a.rings[i].x, b.rings[i].x);
      }
    });

    test('different seeds can produce different ring y sequences', () {
      final a = VooSerenoModel(seed: 1);
      final b = VooSerenoModel(seed: 2);
      for (int i = 0; i < 400; i++) {
        a.update(0.1);
        b.update(0.1);
      }
      final ysA = a.rings.map((r) => r.y).toList();
      final ysB = b.rings.map((r) => r.y).toList();
      expect(ysA, isNot(equals(ysB)));
    });

    test('first ring spawns at y=0.5, subsequent rings clamp within [0.15, 0.85]', () {
      final model = VooSerenoModel(seed: 7);
      // Advance just enough for the first spawn (immediate, at elapsed ~ 0).
      model.update(0.01);
      expect(model.rings, isNotEmpty);
      expect(model.rings.first.y, 0.5);

      for (int i = 0; i < 2000; i++) {
        model.update(0.1);
      }
      for (final ring in model.rings) {
        expect(ring.y, inInclusiveRange(0.15, 0.85));
      }
    });

    test('rings spawn roughly every 8 seconds and are removed once off-screen', () {
      final model = VooSerenoModel(seed: 3);
      final spawnCounts = <int>[];
      for (int i = 0; i < 800; i++) {
        model.update(0.1);
        spawnCounts.add(model.rings.length);
      }
      // At least a handful of rings should have appeared and some removed
      // (80s of simulation / 8s cadence => ~10 spawns, but old ones leave
      // the screen and get pruned, keeping the live list small).
      expect(model.rings.length, lessThan(6));

      // No ring should ever have crossed the removal boundary and still be
      // present.
      for (final ring in model.rings) {
        expect(ring.x, greaterThanOrEqualTo(-0.2));
      }
    });

    test('hit detection: plane aligned with a ring at crossing time counts as a hit', () {
      final model = VooSerenoModel(seed: 9, rhythm: const BreathingRhythm());
      model.update(0.001); // spawn the first ring at y=0.5
      final ring = model.rings.first;
      model.setTarget(ring.y); // keep the plane aligned with the ring's height

      bool sawHitThisFrame = false;
      for (int i = 0; i < 200; i++) {
        model.update(0.05);
        if (model.hitThisFrame) {
          sawHitThisFrame = true;
          expect(model.lastHitRing, isNotNull);
          expect(model.lastHitRing!.hit, isTrue);
          expect(model.lastHitRing!.passed, isTrue);
        } else {
          // hitThisFrame must not remain true beyond the exact frame of the hit.
          if (model.lastHitRing != null && model.lastHitRing!.passed) {
            expect(model.hitThisFrame, isFalse);
          }
        }
      }
      expect(sawHitThisFrame, isTrue);
      expect(model.ringsPassed, greaterThanOrEqualTo(1));
    });

    test('miss detection: ring passes without incrementing ringsPassed when misaligned', () {
      final model = VooSerenoModel(seed: 9);
      model.update(0.001); // spawn the first ring at y=0.5
      final ring = model.rings.first;
      // Keep the plane far from the ring's height (outside ringRadius).
      model.setTarget(ring.y + 0.4);

      for (int i = 0; i < 200; i++) {
        model.update(0.05);
      }
      expect(ring.passed, isTrue);
      expect(ring.hit, isFalse);
      expect(model.ringsPassed, 0);
    });

    test('hitThisFrame is only true during the exact update of a hit, not before or after', () {
      final model = VooSerenoModel(seed: 5);
      model.update(0.001);
      final ring = model.rings.first;
      model.setTarget(ring.y);

      int hitFrames = 0;
      for (int i = 0; i < 200; i++) {
        model.update(0.05);
        if (model.hitThisFrame) hitFrames++;
      }
      // Exactly one frame should have hitThisFrame true for this single ring.
      expect(hitFrames, 1);
    });
  });

  group('round-2 fixes', () {
    test('update(0) is a full no-op: no ring spawned, nothing advances', () {
      final model = VooSerenoModel(seed: 3);
      model.update(0.0);
      expect(model.elapsed, 0.0);
      expect(model.rings, isEmpty);
      model.update(0.01);
      expect(model.rings, hasLength(1));
    });

    test('pitch saturates softly: moderate velocity gives an intermediate angle', () {
      final model = VooSerenoModel();
      model.verticalVelocity = 0.3;
      final double moderate = model.pitchRadians;
      expect(moderate, greaterThan(0.05));
      expect(moderate, lessThan(12 * pi / 180 * 0.9));
      model.verticalVelocity = 50;
      expect(model.pitchRadians, lessThanOrEqualTo(12 * pi / 180 + 1e-9));
      model.verticalVelocity = -50;
      expect(model.pitchRadians, greaterThanOrEqualTo(-12 * pi / 180 - 1e-9));
    });

    test('ring random walk does not stick to the boundaries', () {
      int onEdge = 0;
      int total = 0;
      for (int seed = 0; seed < 20; seed++) {
        final model = VooSerenoModel(seed: seed);
        final seen = <Ring>{};
        for (int i = 0; i < 10000; i++) {
          model.update(0.1);
          for (final ring in model.rings) {
            if (seen.add(ring)) {
              total++;
              if (ring.y == 0.15 || ring.y == 0.85) onEdge++;
            }
          }
        }
      }
      expect(total, greaterThan(1000));
      expect(onEdge / total, lessThan(0.05));
    });

    test('Ring.crossed mirrors passed', () {
      final ring = Ring(x: 1.2, y: 0.5);
      expect(ring.crossed, isFalse);
      ring.passed = true;
      expect(ring.crossed, isTrue);
    });
  });
}
