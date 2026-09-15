import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/calming_games/estrada_tranquila_model.dart';

void main() {
  group('EstradaTranquilaModel', () {
    test('starts centered with no velocity and no items', () {
      final model = EstradaTranquilaModel(seed: 1);
      expect(model.lateral, 0);
      expect(model.lateralVelocity, 0);
      expect(model.touchTarget, isNull);
      expect(model.curve, 0);
      expect(model.items, isEmpty);
      expect(model.portalsPassed, 0);
      expect(model.hitThisFrame, isFalse);
      expect(model.distance, 0);
    });

    test('update clamps dt to 0.1s so a background pause never jumps', () {
      final model = EstradaTranquilaModel(seed: 1);
      model.update(5.0);
      expect(model.elapsed, closeTo(0.1, 1e-9));
      expect(model.distance, closeTo(0.1, 1e-9));

      final model2 = EstradaTranquilaModel(seed: 1);
      model2.update(-3.0);
      expect(model2.elapsed, 0.0);
      expect(model2.distance, 0.0);
    });

    test('update(0) is a full no-op: no spawn, no advance (matches a Ticker\'s first frame)', () {
      final model = EstradaTranquilaModel(seed: 1);
      model.update(0.0);
      expect(model.elapsed, 0.0);
      expect(model.distance, 0.0);
      expect(model.items, isEmpty);
      expect(model.curve, 0.0);
      expect(model.curveTarget, 0.0);

      // The very next update with dt > 0 must behave like the first frame:
      // items/curve start appearing right away.
      model.update(0.01);
      expect(model.elapsed, greaterThan(0.0));
      expect(model.items, isNotEmpty);
    });

    test('item cadence: every item takes at least 6s to travel from z=1.0 to z=0.0', () {
      // Spec principle 2: nothing appears suddenly, everything crosses the
      // screen in >= 6s.
      expect(
        (1.0 + 0.1) / EstradaTranquilaModel.itemSpeed,
        greaterThanOrEqualTo(6.0),
      );

      final model = EstradaTranquilaModel(seed: 2);
      model.update(0.01); // spawns the first post/tree/portal at z=1.0
      expect(model.items, isNotEmpty);
      final RoadItem freshItem = model.items.first;
      expect(freshItem.z, closeTo(1.0, 0.01));

      double elapsedSinceSpawn = 0.01;
      while (freshItem.z > 0.0) {
        model.update(0.1);
        elapsedSinceSpawn += 0.1;
      }
      expect(elapsedSinceSpawn, greaterThanOrEqualTo(6.0));
    });

    test('setTarget clamps to [-1, 1]', () {
      final model = EstradaTranquilaModel(seed: 1);
      model.setTarget(2.0);
      expect(model.touchTarget, 1.0);
      model.setTarget(-2.0);
      expect(model.touchTarget, -1.0);
      model.setTarget(0.3);
      expect(model.touchTarget, 0.3);
    });

    test('releaseTouch makes the car drift back toward the center', () {
      final model = EstradaTranquilaModel(seed: 1);
      model.setTarget(0.9);
      for (int i = 0; i < 50; i++) {
        model.update(0.05);
      }
      expect(model.lateral, closeTo(0.9, 0.05));

      model.releaseTouch();
      expect(model.touchTarget, isNull);
      for (int i = 0; i < 400; i++) {
        model.update(0.05);
      }
      expect(model.lateral, closeTo(0.0, 1e-3));
    });

    test('lateral spring never overshoots a constant target approached from rest', () {
      final model = EstradaTranquilaModel(seed: 1);
      model.setTarget(0.8); // approaching from 0 (below target)
      double previous = model.lateral;
      for (int i = 0; i < 500; i++) {
        model.update(0.02);
        expect(model.lateral, lessThanOrEqualTo(0.8 + 1e-9));
        expect(model.lateral, greaterThanOrEqualTo(previous));
        previous = model.lateral;
      }
      expect(model.lateral, closeTo(0.8, 1e-3));

      final modelNeg = EstradaTranquilaModel(seed: 1);
      modelNeg.setTarget(-0.8); // approaching from 0 (above target)
      double previousNeg = modelNeg.lateral;
      for (int i = 0; i < 500; i++) {
        modelNeg.update(0.02);
        expect(modelNeg.lateral, greaterThanOrEqualTo(-0.8 - 1e-9));
        expect(modelNeg.lateral, lessThanOrEqualTo(previousNeg));
        previousNeg = modelNeg.lateral;
      }
      expect(modelNeg.lateral, closeTo(-0.8, 1e-3));
    });

    test('curveTarget stays within [-0.6, 0.6] and is redrawn deterministically over time', () {
      final model = EstradaTranquilaModel(seed: 11);
      final seenTargets = <double>{model.curveTarget};
      for (int i = 0; i < 3000; i++) {
        model.update(0.1);
        expect(model.curveTarget, inInclusiveRange(-0.6, 0.6));
        expect(model.curve, inInclusiveRange(-0.6, 0.6));
        seenTargets.add(model.curveTarget);
      }
      // 300s of simulation / 10s cadence => curveTarget should have changed
      // multiple times.
      expect(seenTargets.length, greaterThan(1));
    });

    test('deterministic curveTarget and item sequence with the same seed', () {
      final a = EstradaTranquilaModel(seed: 42);
      final b = EstradaTranquilaModel(seed: 42);
      for (int i = 0; i < 400; i++) {
        a.update(0.1);
        b.update(0.1);
      }
      expect(a.curveTarget, b.curveTarget);
      expect(a.curve, b.curve);
      expect(a.items.length, b.items.length);
      for (int i = 0; i < a.items.length; i++) {
        expect(a.items[i].kind, b.items[i].kind);
        expect(a.items[i].side, b.items[i].side);
        expect(a.items[i].z, b.items[i].z);
      }
    });

    test('different seeds can diverge in curveTarget/tree side sequence', () {
      final a = EstradaTranquilaModel(seed: 1);
      final b = EstradaTranquilaModel(seed: 2);
      for (int i = 0; i < 400; i++) {
        a.update(0.1);
        b.update(0.1);
      }
      final treesA = a.items.where((i) => i.kind == RoadItemKind.tree).map((i) => i.side).toList();
      final treesB = b.items.where((i) => i.kind == RoadItemKind.tree).map((i) => i.side).toList();
      expect(treesA, isNot(equals(treesB)));
    });

    test('posts spawn alternating sides', () {
      final model = EstradaTranquilaModel(seed: 3);
      for (int i = 0; i < 400; i++) {
        model.update(0.1);
      }
      final postSides = model.items
          .where((item) => item.kind == RoadItemKind.post)
          .map((item) => item.side)
          .toList();
      expect(postSides.length, greaterThan(1));
      for (int i = 1; i < postSides.length; i++) {
        expect(postSides[i], isNot(equals(postSides[i - 1])));
      }
    });

    test('items are removed once they pass behind the car (z < -0.1)', () {
      final model = EstradaTranquilaModel(seed: 4);
      for (int i = 0; i < 5000; i++) {
        model.update(0.1);
      }
      for (final item in model.items) {
        expect(item.z, greaterThanOrEqualTo(-0.1));
      }
      // Plenty of spawn cadences elapsed (500s of simulation): the live list
      // must stay bounded because old items get pruned.
      expect(model.items.length, lessThan(20));
    });

    test('portal alignment: centered car scores a hit when crossing the portal', () {
      final model = EstradaTranquilaModel(seed: 6);
      model.setTarget(0.0); // stay centered, well within alignment threshold

      bool sawHitThisFrame = false;
      for (int i = 0; i < 200; i++) {
        model.update(0.05);
        if (model.hitThisFrame) sawHitThisFrame = true;
      }
      final portal = model.items
          .cast<RoadItem?>()
          .firstWhere((item) => item!.kind == RoadItemKind.portal, orElse: () => null);
      // Either the portal already passed with a hit recorded on it, or (if it
      // was pruned already) we must have seen the hit frame fire.
      if (portal != null && portal.passed) {
        expect(portal.hit, isTrue);
      }
      expect(model.portalsPassed, greaterThanOrEqualTo(1));
      expect(sawHitThisFrame, isTrue);
    });

    test('portal alignment: off-center car misses the portal (no score, no haptic)', () {
      final model = EstradaTranquilaModel(seed: 6);
      model.setTarget(1.0); // far from center, outside the alignment threshold

      for (int i = 0; i < 200; i++) {
        model.update(0.05);
      }
      final passedPortals = model.items.where(
        (item) => item.kind == RoadItemKind.portal && item.passed,
      );
      for (final portal in passedPortals) {
        expect(portal.hit, isFalse);
      }
      expect(model.portalsPassed, 0);
    });

    test('breathingGlow mirrors the breathing rhythm phase at elapsed time', () {
      final model = EstradaTranquilaModel(seed: 1);
      expect(model.breathingGlow, 0);
      for (int i = 0; i < 40; i++) {
        model.update(0.1);
      }
      expect(model.elapsed, closeTo(4.0, 1e-6));
      expect(model.breathingGlow, closeTo(1.0, 1e-6));
    });
  });
}
