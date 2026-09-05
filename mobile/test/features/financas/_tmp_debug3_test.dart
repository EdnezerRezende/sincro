import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/core/theme.dart';

void main() {
  testWidgets('measure chip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: sincroLightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(builder: (context) {
            final theme = Theme.of(context);
            return Container(
              key: const Key('chip'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(38),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'fatura',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.amber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }),
        ),
      ),
    );
    await tester.pump();
    final box = tester.renderObject<RenderBox>(find.byKey(const Key('chip')));
    // ignore: avoid_print
    print('CHIP SIZE: ${box.size}');

    final textBox = tester.renderObject<RenderBox>(find.text('fatura'));
    // ignore: avoid_print
    print('TEXT SIZE: ${textBox.size}');
  });
}
