import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';

void main() {
  testWidgets('probe theme wiring', (t) async {
    // ignore: avoid_print
    print('RAW sincroLightTheme.primary=${sincroLightTheme.colorScheme.primary} '
        'brightness=${sincroLightTheme.colorScheme.brightness}');
    // ignore: avoid_print
    print('RAW sincroDarkTheme.primary=${sincroDarkTheme.colorScheme.primary} '
        'brightness=${sincroDarkTheme.colorScheme.brightness}');

    for (final dark in [false, true]) {
      await t.pumpWidget(MaterialApp(
        theme: dark ? sincroDarkTheme : sincroLightTheme,
        home: const Scaffold(body: Text('hi')),
      ));
      final ctx = t.element(find.text('hi'));
      final s = Theme.of(ctx).colorScheme;
      // ignore: avoid_print
      print('IN-TREE dark=$dark => brightness=${s.brightness} primary=${s.primary} '
          'secondary=${s.secondary} onSurfaceVariant=${s.onSurfaceVariant}');
    }
  });
}
