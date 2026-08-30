import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/theme.dart';
import '../lib/core/widgets/app_chip.dart';

void main() {
  group('AppChip Height Tests', () {
    testWidgets('Input variant FilterChip height >= 36.0 dp', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: Center(
              child: AppChip(
                label: 'Height Test',
                variant: AppChipVariant.input,
              ),
            ),
          ),
        ),
      );

      final filterChipFinder = find.byType(FilterChip);
      expect(filterChipFinder, findsOneWidget);

      final size = tester.getSize(filterChipFinder);
      print('=== Input Chip Height: ${size.height} dp ===');
      expect(size.height, greaterThanOrEqualTo(36.0),
          reason: 'Input chip height must be >= 36.0 dp (Material Design 3)');
    });

    testWidgets('Filter variant FilterChip height >= 36.0 dp', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: Center(
              child: AppChip(
                label: 'Filter Variant',
                variant: AppChipVariant.filter,
              ),
            ),
          ),
        ),
      );

      final filterChipFinder = find.byType(FilterChip);
      final size = tester.getSize(filterChipFinder);
      print('=== Filter Chip Height: ${size.height} dp ===');
      expect(size.height, greaterThanOrEqualTo(36.0),
          reason: 'Filter chip height must be >= 36.0 dp');
    });

    testWidgets('Suggestion variant FilterChip height >= 36.0 dp', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: Center(
              child: AppChip(
                label: 'Suggestion',
                variant: AppChipVariant.suggestion,
              ),
            ),
          ),
        ),
      );

      final filterChipFinder = find.byType(FilterChip);
      final size = tester.getSize(filterChipFinder);
      print('=== Suggestion Chip Height: ${size.height} dp ===');
      expect(size.height, greaterThanOrEqualTo(36.0),
          reason: 'Suggestion chip height must be >= 36.0 dp');
    });

    testWidgets('Selected chip height >= 36.0 dp', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: Center(
              child: AppChip(
                label: 'Selected',
                variant: AppChipVariant.input,
                selected: true,
              ),
            ),
          ),
        ),
      );

      final filterChipFinder = find.byType(FilterChip);
      final size = tester.getSize(filterChipFinder);
      print('=== Selected Chip Height: ${size.height} dp ===');
      expect(size.height, greaterThanOrEqualTo(36.0),
          reason: 'Selected chip height must be >= 36.0 dp');
    });

    testWidgets('Disabled chip height >= 36.0 dp', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: Center(
              child: AppChip(
                label: 'Disabled',
                variant: AppChipVariant.input,
                enabled: false,
              ),
            ),
          ),
        ),
      );

      final filterChipFinder = find.byType(FilterChip);
      final size = tester.getSize(filterChipFinder);
      print('=== Disabled Chip Height: ${size.height} dp ===');
      expect(size.height, greaterThanOrEqualTo(36.0),
          reason: 'Disabled chip height must be >= 36.0 dp');
    });

    testWidgets('Chip with icon height >= 36.0 dp', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: sincroLightTheme,
          home: Scaffold(
            body: Center(
              child: AppChip(
                label: 'With Icon',
                icon: Icons.favorite,
                variant: AppChipVariant.input,
              ),
            ),
          ),
        ),
      );

      final filterChipFinder = find.byType(FilterChip);
      final size = tester.getSize(filterChipFinder);
      print('=== Icon Chip Height: ${size.height} dp ===');
      expect(size.height, greaterThanOrEqualTo(36.0),
          reason: 'Chip with icon height must be >= 36.0 dp');
    });
  });
}
