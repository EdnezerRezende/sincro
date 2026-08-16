import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/guide/guide_content.dart';
import 'package:sincro_mobile/features/guide/guide_item.dart';
import 'package:flutter/material.dart';

void main() {
  const itemV1 = GuideItem(
    icon: Icons.home_outlined,
    title: 'Item v1',
    description: 'desc',
    version: 1,
  );
  const itemV2 = GuideItem(
    icon: Icons.star_outline,
    title: 'Item v2',
    description: 'desc',
    version: 2,
  );
  final items = [itemV1, itemV2];

  test('returns every item when nothing was ever seen (versaoVista 0)', () {
    expect(itemsToShow(items, 0), [itemV1, itemV2]);
  });

  test('returns only items newer than the last seen version', () {
    expect(itemsToShow(items, 1), [itemV2]);
  });

  test('returns empty when the last seen version covers everything', () {
    expect(itemsToShow(items, 2), isEmpty);
  });

  test('guideItems has 8 entries, all tagged version 1', () {
    expect(guideItems.length, 8);
    expect(guideItems.every((i) => i.version == 1), isTrue);
  });

  test('guiaVersaoAtual matches the highest version used in guideItems', () {
    final maiorVersaoUsada = guideItems.map((i) => i.version).reduce((a, b) => a > b ? a : b);
    expect(guiaVersaoAtual, maiorVersaoUsada);
  });
}
